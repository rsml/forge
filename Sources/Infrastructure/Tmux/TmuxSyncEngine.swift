import Foundation
import ForgeCore

/// Owns the tmux state sync cycle: periodic polling, debounced refresh on events,
/// and state merging via StateMerger. Calls a post-refresh hook for features
/// (e.g., content scanning) to participate in the cycle.
@MainActor
final class TmuxSyncEngine {
    private let workspace: Workspace
    private let tmux: any TmuxPort
    private let git: any GitPort
    private let config: ForgeConfigStore
    private var onPostRefresh: (([StateMerger.PaneEvent]) async -> Void)?

    private var refreshTask: Task<Void, Never>?
    private var refreshDebounceTask: Task<Void, Never>?
    private var isRefreshing = false
    private var needsRefreshAfterCurrent = false
    private var lastGitBranchProjectId: String?
    private(set) var gitBranch: String?

    init(workspace: Workspace, tmux: any TmuxPort, git: any GitPort, config: ForgeConfigStore) {
        self.workspace = workspace
        self.tmux = tmux
        self.git = git
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
        let allWindows = await tmux.listAllTabs()
        let allPanes = await tmux.listAllPanes()

        StateMerger.mergeProjects(workspace, with: sessionInfos)
        let windowsBySession = Dictionary(grouping: allWindows, by: \.projectId)
        let panesByWindow = Dictionary(grouping: allPanes, by: \.tabId)

        var paneEvents: [StateMerger.PaneEvent] = []
        for project in workspace.projects {
            if let activeTabId = StateMerger.mergeTabs(
                project: project, with: windowsBySession[project.id] ?? [],
                activeProjectId: workspace.activeProjectId
            ) {
                workspace.activeTabId = activeTabId
            }
            for tab in project.tabs {
                paneEvents.append(contentsOf: mergePaneState(tab: tab, panesByWindow[tab.id] ?? []))
            }
        }

        await onPostRefresh?(paneEvents)

        let activeProjectId = workspace.activeProjectId
        if activeProjectId != lastGitBranchProjectId {
            lastGitBranchProjectId = activeProjectId
            if let path = workspace.activeProject?.path {
                gitBranch = await git.currentBranch(at: path)
            } else {
                gitBranch = nil
            }
        }
        NotificationCenter.default.post(name: .forgeWindowTitleChanged, object: nil)
    }

    // MARK: - Private

    private func mergePaneState(tab: Tab, _ infos: [PaneInfo]) -> [StateMerger.PaneEvent] {
        let (activePaneId, events) = StateMerger.mergePanes(tab: tab, with: infos)
        if let activePaneId { workspace.activePaneId = activePaneId }
        return events
    }
}
