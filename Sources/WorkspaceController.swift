import AppKit
import Foundation
import Observation
import ForgeCore

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
    private let git: any GitPort
    private var refreshTask: Task<Void, Never>?
    private var refreshDebounceTask: Task<Void, Never>?
    private var isRefreshing = false
    private var needsRefreshAfterCurrent = false
    private var lastGitBranchProjectId: String?
    private var perProjectActiveTabId: [String: String] = [:]  // projectId -> tabId

    init(tmux: any TmuxPort, git: any GitPort) {
        self.tmux = tmux
        self.git = git
    }

    func connect() {
        Task {
            ForgeLog.log("[app] Connecting...")
            await ensureServer()
            if let configPath = tmux.configPath {
                await tmux.sourceConfig(path: configPath)
            }
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
        ForgeLog.log("[app] Removing project: \(project.name)")
        if let index = workspace.projects.firstIndex(where: { $0.id == project.id }) {
            let nextIndex = index > 0 ? index - 1 : min(1, workspace.projects.count - 1)
            if nextIndex != index {
                selectProject(workspace.projects[nextIndex])
            }
        }
        Task { await tmux.killProject(name: project.name) }
    }

    func addTab(in project: Project) {
        ForgeLog.log("[app] Adding tab in project: \(project.name)")
        Task { await tmux.newTab(project: project.id, path: project.path) }
    }

    func removeTab(_ tab: Tab) {
        ForgeLog.log("[app] Removing tab: \(tab.name) (\(tab.id))")
        Task { await tmux.killTab(id: tab.id) }
    }

    /// Removes a tab, selecting the tab to its left (or the next tab if it was first).
    func removeTab(_ tab: Tab, in project: Project) {
        ForgeLog.log("[app] Removing tab: \(tab.name) from \(project.name)")
        if let index = project.tabs.firstIndex(where: { $0.id == tab.id }) {
            let nextIndex = index > 0 ? index - 1 : min(index + 1, project.tabs.count - 1)
            if nextIndex != index, nextIndex < project.tabs.count {
                selectTab(project.tabs[nextIndex])
            }
        }
        Task { await tmux.killTab(id: tab.id) }
    }

    func renameProject(_ project: Project, to name: String) {
        ForgeLog.log("[app] Renaming project: \(project.name) → \(name)")
        Task { await tmux.renameProject(target: project.name, newName: name) }
    }

    func renameTab(_ tab: Tab, to name: String) {
        ForgeLog.log("[app] Renaming tab: \(tab.name) → \(name)")
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
        let config = ForgeConfigStore.shared.config.general
        let decision = CloseConfirmation.evaluate(
            project: project, tab: tab, activePane: activePane,
            warnOnCloseProject: config?.warnOnCloseProject ?? true,
            warnOnCloseTab: config?.warnOnCloseTab ?? false
        )

        if let alert = decision.alert {
            guard CloseConfirmation.present(alert) else { return }
        }

        switch decision.target {
        case .pane(let id):
            Task { await tmux.killPane(id: id) }
        case .tab(let tab, let project):
            removeTab(tab, in: project)
        case .project(let project):
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
        gitBranch = await git.currentBranch(at: path)
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

    private func handleEvent(_ rawEvent: String) {
        ForgeLog.log("[control] \(rawEvent)")

        let event = TmuxEventParser.parse(rawEvent)
        switch event {
        case .bell(let tabId):
            if let (_, tab) = workspace.findTab(byTmuxId: tabId) {
                for pane in tab.panes { pane.hasBell = true }
                attentionManager?.handleEvent(.bell(tabUUID: tab.uuid))
            } else {
                ForgeLog.log("[control] Bell event for unknown tab: \(tabId)")
            }

        case .tabClose(let tabId):
            if let (_, tab) = workspace.findTab(byTmuxId: tabId) {
                attentionManager?.removeTab(tab.uuid)
            }
            scheduleRefresh()

        case .structural:
            scheduleRefresh()

        case .ignored:
            break
        }
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
        StateMerger.mergeProjects(workspace, with: infos)
    }

    private func mergeTabState(project: Project, _ infos: [TabInfo]) {
        if let activeTabId = StateMerger.mergeTabs(project: project, with: infos,
                                                    activeProjectId: workspace.activeProjectId) {
            workspace.activeTabId = activeTabId
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
        let (activePaneId, events) = StateMerger.mergePanes(tab: tab, with: infos)
        if let activePaneId { workspace.activePaneId = activePaneId }
        for event in events {
            switch event {
            case .commandCompleted(let tabUUID):
                attentionManager?.handleEvent(.commandCompleted(tabUUID: tabUUID))
            }
        }
    }
}
