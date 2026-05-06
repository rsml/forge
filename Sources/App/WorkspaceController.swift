import AppKit
import Foundation
import Observation
import ForgeDomain

/// Orchestrates domain state and tmux adapter.
/// Single @Observable object that all views consume.
@Observable
@MainActor
final class WorkspaceController {
    let workspace = Workspace()
    var attentionManager: AttentionManager?
    let contentDetector = ContentDetector()
    private(set) var gitBranch: String?
    private let tmux: any TmuxPort
    private var refreshTask: Task<Void, Never>?
    private var refreshDebounceTask: Task<Void, Never>?
    private var isRefreshing = false
    private var needsRefreshAfterCurrent = false
    private var lastGitBranchProjectId: String?
    private var perProjectActiveTabId: [String: String] = [:]  // projectId -> tabId

    init(tmux: any TmuxPort) {
        self.tmux = tmux
    }

    func connect() {
        Task {
            ForgeLog.log("[app] Connecting...")
            await ensureServer()
            await refresh()
            seedRecentDirectories()
            restoreUIState()
            // Prune any hidden UUIDs from a previous project that no longer exist
            let allUUIDs = Set(workspace.projects.flatMap { $0.tabs.map(\.uuid) })
            attentionManager?.pruneStaleHiddenEntries(validUUIDs: allUUIDs)

            tmux.startControlMode { [weak self] event in
                Task { @MainActor in
                    self?.handleEvent(event)
                }
            }

            startPeriodicRefresh()
            workspace.connected = true
            ForgeLog.log("[app] Connected. \(workspace.projects.count) sessions found.")
        }
    }

    func disconnect() {
        refreshTask?.cancel()
        tmux.stopControlMode()
    }

    // MARK: - State Refresh

    func refresh() async {
        let sessionInfos = await tmux.listProjects()
        let allWindows = await tmux.listAllTabs()
        let allPanes = await tmux.listAllPanes()

        mergeProjectState(sessionInfos)
        let windowsBySession = Dictionary(grouping: allWindows, by: \.projectId)
        let panesByWindow = Dictionary(grouping: allPanes, by: \.tabId)

        for project in workspace.projects {
            mergeTabState(project: project, windowsBySession[project.id] ?? [])
            for tab in project.tabs {
                mergePaneState(tab: tab, panesByWindow[tab.id] ?? [])
            }
        }

        // Content-based attention detection for running panes
        let patterns = ContentDetector.defaultPatterns
            + (ForgeConfigStore.shared.config.stackView?.contentPatterns ?? [])
        for project in workspace.projects {
            for tab in project.tabs {
                for pane in tab.panes where pane.status == .running {
                    if let content = await tmux.capturePaneContent(id: pane.id, lastN: pane.height) {
                        let isNewMatch = contentDetector.scan(
                            paneId: pane.id, content: content, patterns: patterns
                        )
                        if isNewMatch {
                            ForgeLog.log("[attention] Content match in pane \(pane.id): \(content.suffix(80))")
                            pane.hasContentMatch = true
                            attentionManager?.handleEvent(.contentMatch(tabUUID: tab.uuid))
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

        let activeProjectId = workspace.activeProjectId
        if activeProjectId != lastGitBranchProjectId {
            lastGitBranchProjectId = activeProjectId
            await fetchGitBranch()
        }
        NotificationCenter.default.post(name: .forgeWindowTitleChanged, object: nil)
    }

    // MARK: - Actions

    enum StackDismissAction {
        case done, hide, moveToBack
    }

    func stackDismiss(_ action: StackDismissAction) {
        guard let attention = attentionManager,
              let uuid = attention.currentTabUUID else { return }
        switch action {
        case .done:
            if let (_, tab) = workspace.findTab(byUUID: uuid) {
                for pane in tab.panes {
                    pane.hasBell = false
                    pane.hasContentMatch = false
                }
            }
            attention.markDone(uuid)
        case .hide:
            attention.hide(uuid)
        case .moveToBack:
            attention.moveToBack(uuid)
        }
    }

    func selectProject(_ project: Project) {
        // Save current tab for the project we're leaving
        if let currentSessionId = workspace.activeProjectId {
            perProjectActiveTabId[currentSessionId] = workspace.activeTabId
        }

        workspace.activeProjectId = project.id

        // Restore saved tab for the project we're entering
        if let savedWindowId = perProjectActiveTabId[project.id],
           project.tabs.contains(where: { $0.id == savedWindowId }) {
            workspace.activeTabId = savedWindowId
            Task { await tmux.selectTab(id: savedWindowId) }
        } else if let tab = project.tabs.first(where: { $0.active }) ?? project.tabs.first {
            workspace.activeTabId = tab.id
        }

        Task { await tmux.switchClient(project: project.name) }
        saveUIState()
    }

    func selectTab(_ tab: Tab) {
        workspace.activeTabId = tab.id
        Task { await tmux.selectTab(id: tab.id) }
        saveUIState()
    }

    func addProject(name: String, path: String) async {
        await tmux.newProject(name: name, path: path)
        await refresh()
        if let project = workspace.projects.first(where: { $0.name == name }) {
            selectProject(project)
        }
    }

    func removeProject(_ project: Project) {
        if let index = workspace.projects.firstIndex(where: { $0.id == project.id }) {
            let nextIndex = index > 0 ? index - 1 : min(1, workspace.projects.count - 1)
            if nextIndex != index {
                selectProject(workspace.projects[nextIndex])
            }
        }
        Task { await tmux.killProject(name: project.name) }
    }

    func addTab(in project: Project) {
        Task { await tmux.newTab(project: project.id, path: project.path) }
    }

    func removeTab(_ tab: Tab) {
        Task { await tmux.killTab(id: tab.id) }
    }

    /// Removes a tab, selecting the tab to its left (or the next tab if it was first).
    func removeTab(_ tab: Tab, in project: Project) {
        if let index = project.tabs.firstIndex(where: { $0.id == tab.id }) {
            let nextIndex = index > 0 ? index - 1 : min(index + 1, project.tabs.count - 1)
            if nextIndex != index, nextIndex < project.tabs.count {
                selectTab(project.tabs[nextIndex])
            }
        }
        Task { await tmux.killTab(id: tab.id) }
    }

    func renameProject(_ project: Project, to name: String) {
        Task { await tmux.renameProject(target: project.name, newName: name) }
    }

    func renameTab(_ tab: Tab, to name: String) {
        Task { await tmux.renameTab(id: tab.id, newName: name) }
    }

    /// Closes the current pane (like tmux prefix+x). Cascades:
    /// multiple panes → kill pane; one pane + multiple tabs → kill tab; last tab → close project.
    /// Confirms if a process is running.
    func closeCurrentPane() {
        guard let project = workspace.activeProject,
              let tabId = workspace.activeTabId,
              let tab = project.tabs.first(where: { $0.id == tabId })
        else { return }

        let activePane = tab.panes.first(where: { $0.active }) ?? tab.panes.first
        let hasMultiplePanes = tab.panes.count > 1
        let hasMultipleWindows = project.tabs.count > 1

        // Check if a non-shell process is running
        let isRunning = activePane?.status == .running

        if isRunning {
            let processName = tab.name
            let alert = NSAlert()
            if hasMultiplePanes {
                alert.messageText = "Close this pane?"
                alert.informativeText = "\"\(processName)\" is running in this pane."
                alert.addButton(withTitle: "Close Pane")
            } else if hasMultipleWindows {
                alert.messageText = "Close this tab?"
                alert.informativeText = "\"\(processName)\" is running in this tab."
                alert.addButton(withTitle: "Close Tab")
            } else {
                alert.messageText = "Close project \"\(project.name)\"?"
                alert.informativeText = "\"\(processName)\" is running."
                alert.addButton(withTitle: "Close Project")
            }
            alert.addButton(withTitle: "Cancel")
            alert.alertStyle = .warning
            guard alert.runModal() == .alertFirstButtonReturn else { return }
        } else {
            // Settings-based warnings when no process is running
            let config = ForgeConfigStore.shared.config.general
            if !hasMultiplePanes && !hasMultipleWindows && (config?.warnOnCloseProject ?? true) {
                let alert = NSAlert()
                alert.messageText = "Close project \"\(project.name)\"?"
                alert.informativeText = "This will close all tabs and remove the project from Forge."
                alert.addButton(withTitle: "Close Project")
                alert.addButton(withTitle: "Cancel")
                alert.alertStyle = .warning
                guard alert.runModal() == .alertFirstButtonReturn else { return }
            } else if !hasMultiplePanes && hasMultipleWindows && (config?.warnOnCloseTab ?? false) {
                let alert = NSAlert()
                alert.messageText = "Close tab \"\(tab.name)\"?"
                alert.informativeText = "This tab will be closed."
                alert.addButton(withTitle: "Close Tab")
                alert.addButton(withTitle: "Cancel")
                alert.alertStyle = .warning
                guard alert.runModal() == .alertFirstButtonReturn else { return }
            }
        }

        if hasMultiplePanes, let pane = activePane {
            Task { await tmux.killPane(id: pane.id) }
        } else if hasMultipleWindows {
            removeTab(tab, in: project)
        } else {
            removeProject(project)
        }
    }

    func moveTab(_ tab: Tab, from source: Project, to target: Project) {
        if ForgeConfigStore.shared.config.general?.warnOnMoveTab ?? true {
            let alert = NSAlert()
            alert.messageText = "Move tab to \"\(target.name)\"?"
            alert.informativeText = "\"\(tab.name)\" will be moved from \"\(source.name)\"."
            alert.addButton(withTitle: "Move Tab")
            alert.addButton(withTitle: "Cancel")
            alert.showsSuppressionButton = true
            alert.suppressionButton?.title = "Don't ask again"
            alert.alertStyle = .informational
            guard alert.runModal() == .alertFirstButtonReturn else { return }
            if alert.suppressionButton?.state == .on {
                ForgeConfigStore.shared.update { config in
                    if config.general == nil { config.general = ForgeConfig.GeneralSettings() }
                    config.general!.warnOnMoveTab = false
                }
            }
        }

        // Optimistic update
        if let idx = source.tabs.firstIndex(where: { $0.id == tab.id }) {
            source.tabs.remove(at: idx)
        }
        target.tabs.append(tab)

        // If the moved tab was active, select the next available
        if source.id == workspace.activeProjectId, workspace.activeTabId == tab.id {
            if let next = source.tabs.first {
                selectTab(next)
            }
        }

        Task { await tmux.moveTab(id: tab.id, toSession: target.name) }
    }

    func clearScrollback() {
        guard let paneId = workspace.activePaneId else { return }
        Task { await tmux.clearHistory(pane: paneId) }
    }

    func splitPane(direction: SplitDirection) {
        guard let tabId = workspace.activeTabId else { return }
        Task { await tmux.splitWindow(id: tabId, direction: direction) }
    }

    func reorderTab(in project: Project, from: Int, to: Int) {
        guard from >= 0, from < project.tabs.count else { return }
        let tab = project.tabs[from]

        // Collect swap targets before optimistic update changes the array
        let finalIndex = to > from ? to - 1 : to
        var targets: [String] = []
        if from < finalIndex {
            for i in (from + 1)...finalIndex {
                targets.append(project.tabs[i].id)
            }
        } else if from > finalIndex {
            for i in stride(from: from - 1, through: finalIndex, by: -1) {
                targets.append(project.tabs[i].id)
            }
        }

        // Optimistic update
        project.tabs.move(fromOffsets: IndexSet(integer: from), toOffset: to)

        guard !targets.isEmpty else { return }
        Task { await tmux.reorderTab(id: tab.id, swapWith: targets) }
    }

    func swapTab(offset: Int) {
        guard let project = workspace.activeProject,
              let tabId = workspace.activeTabId,
              let fromIndex = project.tabs.firstIndex(where: { $0.id == tabId })
        else { return }
        let toIndex = fromIndex + offset
        guard toIndex >= 0, toIndex < project.tabs.count else { return }
        project.tabs.swapAt(fromIndex, toIndex)
        Task { await tmux.swapTab(id: tabId, offset: offset) }
    }

    // MARK: - Private

    private func fetchGitBranch() async {
        guard let path = workspace.activeProject?.path else {
            gitBranch = nil
            return
        }
        let result: String? = await withCheckedContinuation { cont in
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
        gitBranch = result
    }

    private func ensureServer() async {
        let sessions = await tmux.listProjects()
        if sessions.isEmpty {
            // Clean up stale socket if a previous server crashed
            let socketPath = "/private/tmp/tmux-\(getuid())/forge"
            if FileManager.default.fileExists(atPath: socketPath) {
                try? FileManager.default.removeItem(atPath: socketPath)
                ForgeLog.log("[app] Removed stale tmux socket")
            }
            await tmux.newProject(name: "forge-default", path: NSHomeDirectory())
        }
    }

    private func handleEvent(_ event: String) {
        ForgeLog.log("[control] \(event)")

        if event.hasPrefix("%bell") {
            // %bell <window_id> — mark panes in that tab as having bell, no refresh needed
            let parts = event.split(separator: " ")
            if parts.count >= 2 {
                let tabId = String(parts[1])
                var found = false
                for project in workspace.projects {
                    if let tab = project.tabs.first(where: { $0.id == tabId }) {
                        for pane in tab.panes {
                            pane.hasBell = true
                        }
                        found = true
                        attentionManager?.handleEvent(.bell(tabUUID: tab.uuid))
                        break
                    }
                }
                if !found {
                    ForgeLog.log("[control] Bell event for unknown tab: \(tabId)")
                }
            }
            return
        }

        if event.hasPrefix("%tab-close") || event.hasPrefix("%unlinked-tab-close") {
            let parts = event.split(separator: " ")
            if parts.count >= 2 {
                let tabId = String(parts[1])
                if let (_, tab) = workspace.findTab(byTmuxId: tabId) {
                    attentionManager?.removeTab(tab.uuid)
                }
            }
        }

        // Structural events that require a state refresh
        let structuralPrefixes = [
            "%tab-add", "%tab-close", "%unlinked-tab-close",
            "%layout-change",
            "%project-changed", "%project-renamed",
            "%tab-renamed",
        ]
        let isStructural = structuralPrefixes.contains { event.hasPrefix($0) }

        if isStructural {
            scheduleRefresh()
        }
        // Informational events (%begin, %end, %error, %pane-mode-changed, etc.) — no action needed
    }

    private func scheduleRefresh() {
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

    private func startPeriodicRefresh() {
        refreshTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(5))
                await refresh()
            }
        }
    }

    private func mergeProjectState(_ infos: [ProjectInfo]) {
        let infoById = Dictionary(uniqueKeysWithValues: infos.map { ($0.id, $0) })

        // Update existing sessions in-place (preserves local order)
        for project in workspace.projects {
            if let info = infoById[project.id] {
                project.name = info.name
                project.tabCount = info.tabCount
                project.attached = info.attached
                project.path = info.path
            }
        }

        // Remove sessions that no longer exist in tmux
        let liveIds = Set(infos.map(\.id))
        let oldActiveId = workspace.activeProjectId
        let oldIndex = oldActiveId.flatMap { id in workspace.projects.firstIndex(where: { $0.id == id }) }
        let removedActive = oldActiveId.map { !liveIds.contains($0) } ?? false

        workspace.projects.removeAll { !liveIds.contains($0.id) }

        // Append new sessions (not yet in local array)
        let existingIds = Set(workspace.projects.map(\.id))
        for info in infos where !existingIds.contains(info.id) {
            workspace.projects.append(Project(id: info.id, name: info.name,
                                              tabCount: info.tabCount,
                                              attached: info.attached, path: info.path))
        }

        // If the active project was removed, select its neighbor
        if removedActive, !workspace.projects.isEmpty {
            let fallbackIndex: Int
            if let oldIndex {
                fallbackIndex = oldIndex > 0 ? oldIndex - 1 : 0
            } else {
                fallbackIndex = 0
            }
            let target = workspace.projects[min(fallbackIndex, workspace.projects.count - 1)]
            workspace.activeProjectId = target.id
            if let tab = target.tabs.first(where: { $0.active }) ?? target.tabs.first {
                workspace.activeTabId = tab.id
            }
        } else if workspace.activeProjectId == nil, let first = workspace.projects.first {
            workspace.activeProjectId = first.id
        }
    }

    private func mergeTabState(project: Project, _ infos: [TabInfo]) {
        let infoById = Dictionary(uniqueKeysWithValues: infos.map { ($0.id, $0) })

        // Update existing windows in-place (preserves local order from drag reorder)
        for tab in project.tabs {
            if let info = infoById[tab.id] {
                tab.index = info.index
                tab.name = info.name
                tab.active = info.active
            }
        }

        // Remove windows that no longer exist in tmux
        let liveIds = Set(infos.map(\.id))
        project.tabs.removeAll { !liveIds.contains($0.id) }

        // Append new windows
        let existingIds = Set(project.tabs.map(\.id))
        for info in infos where !existingIds.contains(info.id) {
            project.tabs.append(Tab(id: info.id, projectId: info.projectId,
                                         index: info.index, name: info.name, active: info.active))
        }

        if let active = infos.first(where: { $0.active }) {
            if project.id == workspace.activeProjectId {
                workspace.activeTabId = active.id
            }
        }
    }

    // MARK: - UI State Persistence

    func saveUIState(sidebarVisible: Bool? = nil, expandedProjectNames: [String]? = nil) {
        let activeProject = workspace.projects.first { $0.id == workspace.activeProjectId }
        let activeWindow = activeProject?.tabs.first { $0.id == workspace.activeTabId }

        ForgeConfigStore.shared.update { config in
            var state = config.uiState ?? ForgeConfig.UIState()
            state.activeProjectName = activeProject?.name
            state.activeTabIndex = activeWindow?.index
            if let sidebarVisible { state.sidebarVisible = sidebarVisible }
            if let expandedProjectNames { state.expandedProjectNames = expandedProjectNames }
            config.uiState = state
        }
    }

    private func seedRecentDirectories() {
        let paths = workspace.projects.compactMap { project -> String? in
            guard let path = project.path, !path.isEmpty, path != NSHomeDirectory() else { return nil }
            return path
        }
        guard !paths.isEmpty else { return }
        ForgeConfigStore.shared.update { config in
            for path in paths where !config.recentDirectories.contains(path) {
                config.recentDirectories.append(path)
            }
            if config.recentDirectories.count > 20 {
                config.recentDirectories = Array(config.recentDirectories.prefix(20))
            }
        }
    }

    private func restoreUIState() {
        guard let state = ForgeConfig.load().uiState else { return }

        // Restore active project by name
        if let name = state.activeProjectName,
           let project = workspace.projects.first(where: { $0.name == name }) {
            workspace.activeProjectId = project.id
            Task { await tmux.switchClient(project: project.name) }

            // Restore active tab by index within that project
            if let index = state.activeTabIndex,
               let tab = project.tabs.first(where: { $0.index == index }) {
                workspace.activeTabId = tab.id
                Task { await tmux.selectTab(id: tab.id) }
            } else if let first = project.tabs.first {
                workspace.activeTabId = first.id
            }
        }
    }

    private func mergePaneState(tab: Tab, _ infos: [PaneInfo]) {
        var updated: [Pane] = []
        for info in infos {
            if let existing = tab.panes.first(where: { $0.id == info.id }) {
                existing.index = info.index
                existing.active = info.active
                // Detect command completion: running → idle transition
                let wasRunning = PaneStatus.from(command: existing.currentCommand) == .running
                let nowIdle = PaneStatus.from(command: info.currentCommand) == .idle
                if wasRunning && nowIdle {
                    attentionManager?.handleEvent(.commandCompleted(tabUUID: tab.uuid))
                }
                // Clear bell when pane resumes: idle → running transition
                let wasIdle = PaneStatus.from(command: existing.currentCommand) == .idle
                let nowRunning = PaneStatus.from(command: info.currentCommand) == .running
                if wasIdle && nowRunning {
                    existing.hasBell = false
                }
                existing.previousCommand = existing.currentCommand
                existing.currentCommand = info.currentCommand
                existing.currentPath = info.currentPath
                existing.width = info.width
                existing.height = info.height
                existing.pid = info.pid
                existing.status = existing.hasBell ? .needsAttention : PaneStatus.from(command: info.currentCommand)
                updated.append(existing)
            } else {
                updated.append(Pane(id: info.id, tabId: info.tabId, index: info.index,
                                   active: info.active, currentCommand: info.currentCommand,
                                   currentPath: info.currentPath, width: info.width,
                                   height: info.height, pid: info.pid))
            }
        }
        tab.panes = updated
        if let active = infos.first(where: { $0.active }) {
            workspace.activePaneId = active.id
        }
    }
}
