import Foundation
import ForgeCore

/// Owns the tmux state sync cycle: periodic polling, debounced refresh on events,
/// and state merging via StateMerger. Calls a post-refresh hook for features
/// (e.g., content scanning) to participate in the cycle.
@MainActor
final class TmuxSyncEngine {
    private let workspace: Workspace
    private let tmux: any TmuxPort
    private let config: ForgeConfigStore
    private var onPostRefresh: (([StateMerger.PaneEvent]) async -> Void)?

    private var refreshTask: Task<Void, Never>?
    private var refreshDebounceTask: Task<Void, Never>?
    private var isRefreshing = false
    private var needsRefreshAfterCurrent = false
    private var lastGitBranchProjectId: String?
    private(set) var gitBranch: String?
    private let contentDetector = ContentDetector()
    /// Tracks when a tab first became non-silent. hasBell only clears after
    /// sustained non-silence (> 5s), avoiding flicker from brief activity like tab selection.
    private var nonSilentSince: [String: Date] = [:]

    init(workspace: Workspace, tmux: any TmuxPort, config: ForgeConfigStore) {
        self.workspace = workspace
        self.tmux = tmux
        self.config = config
    }

    func setPostRefreshHook(_ hook: @escaping ([StateMerger.PaneEvent]) async -> Void) {
        onPostRefresh = hook
    }

    func start() {
        refreshTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(5))
                await refresh()
            }
        }
    }

    func stop() {
        refreshTask?.cancel()
    }

    func scheduleRefresh() {
        if isRefreshing {
            needsRefreshAfterCurrent = true
            return
        }
        refreshDebounceTask?.cancel()
        refreshDebounceTask = Task {
            try? await Task.sleep(for: .milliseconds(150))
            guard !Task.isCancelled else { return }
            isRefreshing = true
            await refresh()
            isRefreshing = false
            if needsRefreshAfterCurrent {
                needsRefreshAfterCurrent = false
                scheduleRefresh()
            }
        }
    }

    func refresh() async {
        let sessionInfos = await tmux.listProjects()
        // Empty results while workspace has projects means the tmux query failed
        // (e.g., during control mode reconnect after session kill). Skip this
        // refresh — the next cycle will pick up the correct state.
        guard !sessionInfos.isEmpty || workspace.projects.isEmpty else { return }
        let allWindows = await tmux.listAllTabs()
        let allPanes = await tmux.listAllPanes()

        StateMerger.mergeProjects(workspace, with: sessionInfos)
        let windowsBySession = Dictionary(grouping: allWindows, by: \.projectId)
        let panesByWindow = Dictionary(grouping: allPanes, by: \.tabId)

        var paneEvents: [StateMerger.PaneEvent] = []
        let now = Date().timeIntervalSince1970
        let tabInfoById = Dictionary(allWindows.map { ($0.id, $0) }, uniquingKeysWith: { $1 })
        for project in workspace.projects {
            if let activeTabId = StateMerger.mergeTabs(
                project: project, with: windowsBySession[project.id] ?? [],
                activeProjectId: workspace.activeProjectId
            ) {
                let currentTabExists = project.tabs.contains { $0.id == workspace.activeTabId }
                if !currentTabExists {
                    workspace.activeTabId = activeTabId
                }
            }
            for tab in project.tabs {
                paneEvents.append(contentsOf: mergePaneState(tab: tab, panesByWindow[tab.id] ?? []))

                guard let info = tabInfoById[tab.id] else { continue }
                let hasRunningPanes = tab.panes.contains { $0.status == .running }
                let hadBell = tab.panes.contains(where: \.hasBell)

                if info.hasBell {
                    nonSilentSince[tab.id] = nil
                    if !hadBell {
                        for pane in tab.panes where pane.status == .running { pane.hasBell = true }
                        if hasRunningPanes {
                            paneEvents.append(.bell(tabUUID: tab.uuid))
                        }
                    }
                } else if hadBell && hasRunningPanes {
                    // Only clear after sustained non-silence (> 5s).
                    // Tab selection causes brief non-silence (< 2s) then restores.
                    let since = nonSilentSince[tab.id] ?? {
                        nonSilentSince[tab.id] = Date()
                        return Date()
                    }()
                    if Date().timeIntervalSince(since) > 5 {
                        for pane in tab.panes { pane.hasBell = false }
                        paneEvents.append(.silenceCleared(tabUUID: tab.uuid))
                        nonSilentSince[tab.id] = nil
                    }
                } else {
                    nonSilentSince[tab.id] = nil
                }
            }
        }

        let contentEvents = await scanContentMatches()
        paneEvents.append(contentsOf: contentEvents)

        await onPostRefresh?(paneEvents)

        let activeProjectId = workspace.activeProjectId
        if activeProjectId != lastGitBranchProjectId {
            lastGitBranchProjectId = activeProjectId
            if let path = workspace.activeProject?.path {
                gitBranch = await currentBranch(at: path)
            } else {
                gitBranch = nil
            }
        }
        NotificationCenter.default.post(name: .forgeWindowTitleChanged, object: nil)
    }

    // MARK: - Private

    private func scanContentMatches() async -> [StateMerger.PaneEvent] {
        let patterns = ContentDetector.defaultPatterns
            + (config.config.stackView?.contentPatterns ?? [])
        var events: [StateMerger.PaneEvent] = []
        for project in workspace.projects {
            for tab in project.tabs {
                for pane in tab.panes where pane.status == .running {
                    if let content = await tmux.capturePaneContent(id: pane.id, lastN: pane.height) {
                        if contentDetector.scan(paneId: pane.id, content: content, patterns: patterns) {
                            ForgeLog.log("[attention] Content match in pane \(pane.id): \(content.suffix(80))")
                            pane.hasContentMatch = true
                            events.append(.contentMatch(tabUUID: tab.uuid))
                        }
                    }
                }
                for pane in tab.panes where pane.hasContentMatch {
                    if !contentDetector.isActive(paneId: pane.id) {
                        pane.hasContentMatch = false
                    }
                }
            }
        }
        return events
    }

    private func mergePaneState(tab: Tab, _ infos: [PaneInfo]) -> [StateMerger.PaneEvent] {
        let (activePaneId, events) = StateMerger.mergePanes(tab: tab, with: infos)
        if let activePaneId { workspace.activePaneId = activePaneId }
        return events
    }

    private func currentBranch(at path: String) async -> String? {
        await withCheckedContinuation { cont in
            let process = Process()
            let pipe = Pipe()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
            process.arguments = ["-C", path, "rev-parse", "--abbrev-ref", "HEAD"]
            process.standardOutput = pipe
            process.standardError = FileHandle.nullDevice
            do {
                try process.run()
                process.waitUntilExit()
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                let branch = String(data: data, encoding: .utf8)?
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                cont.resume(returning: (branch?.isEmpty == false) ? branch : nil)
            } catch {
                cont.resume(returning: nil)
            }
        }
    }
}
