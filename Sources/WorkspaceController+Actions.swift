import AppKit
import ForgeCore

/// Project/tab lifecycle commands — thin delegation to the tmux port.
extension WorkspaceController {

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
        if let currentSessionId = workspace.activeProjectId {
            perProjectActiveTabId[currentSessionId] = workspace.activeTabId
        }

        workspace.activeProjectId = project.id

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
        let success = await tmux.newProject(name: name, path: path)
        guard success else {
            toastState.show(
                title: "Failed to create project",
                message: "Could not create tmux session \"\(name)\"",
                icon: "exclamationmark.triangle.fill"
            )
            return
        }
        await syncEngine.refresh()
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

    func closeCurrentPane() {
        guard let project = workspace.activeProject,
              let tabId = workspace.activeTabId,
              let tab = project.tabs.first(where: { $0.id == tabId })
        else { return }

        let activePane = tab.panes.first(where: { $0.active }) ?? tab.panes.first
        let generalConfig = config.config.general
        let decision = CloseConfirmation.evaluate(
            project: project, tab: tab, activePane: activePane,
            warnOnCloseProject: generalConfig?.warnOnCloseProject ?? true,
            warnOnCloseTab: generalConfig?.warnOnCloseTab ?? false
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
        let warnOnMove = config.config.general?.warnOnMoveTab ?? true
        if let alertInfo = MoveTabConfirmation.evaluate(
            tabName: tab.name, sourceProjectName: source.name,
            targetProjectName: target.name, warnOnMoveTab: warnOnMove
        ) {
            let alert = NSAlert()
            alert.messageText = alertInfo.message
            alert.informativeText = alertInfo.info
            alert.addButton(withTitle: alertInfo.action)
            alert.addButton(withTitle: "Cancel")
            alert.showsSuppressionButton = true
            alert.suppressionButton?.title = alertInfo.suppressionLabel
            alert.alertStyle = .informational
            guard alert.runModal() == .alertFirstButtonReturn else { return }
            if alert.suppressionButton?.state == .on {
                config.update { config in
                    if config.general == nil { config.general = ForgeConfig.GeneralSettings() }
                    config.general!.warnOnMoveTab = false
                }
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

        let ids = project.tabs.map(\.id)
        let targets = TabReordering.swapTargets(fromIndex: from, toIndex: to, ids: ids)

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
}
