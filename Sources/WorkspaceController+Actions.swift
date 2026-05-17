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
                clearAttention(tab: tab)
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

        saveUIState()
        // switchClient must complete before updateRenderers — resize commands
        // only work when the control mode client is attached to the correct session.
        Task {
            await tmux.switchClient(project: project.name)
            updateRenderers()
        }
    }

    func selectTab(_ tab: Tab) {
        workspace.activeTabId = tab.id
        Task { await tmux.selectTab(id: tab.id) }
        saveUIState()
        updateRenderers()
    }

    /// Navigate to a specific project + tab in one atomic update.
    /// Avoids the flicker from selectProject (which restores a saved tab) + selectTab.
    func navigateToTab(_ tab: Tab, in project: Project) {
        if let currentSessionId = workspace.activeProjectId {
            perProjectActiveTabId[currentSessionId] = workspace.activeTabId
        }
        workspace.activeProjectId = project.id
        workspace.activeTabId = tab.id
        Task { await tmux.selectTab(id: tab.id) }
        saveUIState()
        Task {
            await tmux.switchClient(project: project.name)
            updateRenderers()
        }
    }

    /// Switch tmux to a different window without updating workspace state.
    /// Used by stack dismiss animation to pre-switch the terminal while the
    /// snapshot flyout covers the transition.
    func switchTerminalWindow(tabId: String) {
        Task { await tmux.selectTab(id: tabId) }
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
        if expectingDisconnect {
            expectingDisconnect = false
            startControlMode()
        }

        if let adapter = tmux as? TmuxAdapter {
            await restoreSession(name: name, path: path, adapter: adapter)
        }

        await syncEngine.refresh()
        if let project = workspace.projects.first(where: { $0.name == name }) {
            selectProject(project)
            if config.isStackMode, let tab = project.tabs.first {
                attentionManager?.promoteToFront(tab.uuid)
            }
        }
    }

    func removeProject(_ project: Project) async {
        ForgeLog.log("[app] Removing project: \(project.name)")
        // Killing any session may disconnect control mode (if it's attached to
        // that session). Set the flag so onDisconnect suppresses the toast.
        expectingDisconnect = true

        // Snapshot tab layout before kill
        if let path = project.path {
            if let snapshot = await (tmux as? TmuxAdapter)?.captureSessionSnapshot(project: project.name, path: path) {
                SessionSnapshotStore.save(snapshot)
            }
        }

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
        Task {
            guard let windowId = await tmux.newTab(project: project.id, path: project.path) else { return }
            await syncEngine.refresh()
            if let tab = project.tabs.first(where: { $0.id == windowId }) {
                selectTab(tab)
                if config.isStackMode {
                    attentionManager?.promoteToFront(tab.uuid)
                }
            }
        }
    }

    func removeTab(_ tab: Tab) {
        ForgeLog.log("[app] Removing tab: \(tab.name) (\(tab.id))")
        Task {
            await tmux.killTab(id: tab.id)
            await syncEngine.refresh()
        }
    }

    func removeTab(_ tab: Tab, in project: Project) {
        ForgeLog.log("[app] Removing tab: \(tab.name) from \(project.name)")
        // Compute neighbor before kill — refresh will remove the tab from the model.
        let neighborTab: Tab? = {
            guard let index = project.tabs.firstIndex(where: { $0.id == tab.id }) else { return nil }
            let nextIndex = index > 0 ? index - 1 : min(index + 1, project.tabs.count - 1)
            guard nextIndex != index, nextIndex < project.tabs.count else { return nil }
            return project.tabs[nextIndex]
        }()
        Task {
            await tmux.killTab(id: tab.id)
            await syncEngine.refresh()
            if let neighborTab { selectTab(neighborTab) }
        }
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
        if config.isNativePTY {
            closeCurrentPaneNativePTY()
            return
        }

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
            Task { await removeProject(project) }
        }
    }

    private func closeCurrentPaneNativePTY() {
        guard let project = workspace.activeProject,
              let tabId = workspace.activeTabId,
              let tab = project.tabs.first(where: { $0.id == tabId })
        else { return }

        // Find the focused pane
        let paneIndex: Int = {
            if let focusedId = lastFocusedPaneId,
               let idx = tab.panes.firstIndex(where: { $0.id == focusedId }) {
                return idx
            }
            return max(tab.panes.count - 1, 0)
        }()

        guard paneIndex < tab.panes.count else { return }
        let paneToClose = tab.panes[paneIndex]

        // If it's the last pane, close the tab/project
        if tab.panes.count <= 1 {
            if project.tabs.count <= 1 {
                // Last tab in project — remove project
                workspace.projects.removeAll { $0.id == project.id }
                if workspace.projects.isEmpty {
                    // Create a fresh default project
                    let id = UUID().uuidString
                    let p = Project(id: id, name: "default", path: NSHomeDirectory())
                    let t = Tab(id: UUID().uuidString, projectId: id, index: 0, name: "zsh")
                    t.panes.append(Pane(id: UUID().uuidString, tabId: t.id, currentPath: NSHomeDirectory()))
                    p.tabs.append(t)
                    workspace.projects.append(p)
                    workspace.activeProjectId = id
                    workspace.activeTabId = t.id
                }
            }
            // Just let the renderer be cleaned up by updateRenderers
        } else {
            // Remove the pane and update the split tree
            tab.panes.remove(at: paneIndex)

            // Collapse the split tree: remove the Nth leaf
            if let tree = tab.splitTree {
                var leafIndex = 0
                tab.splitTree = removeLeafAt(node: tree, targetLeaf: paneIndex, currentLeaf: &leafIndex)
            }

            // If only 1 pane left, clear the tree
            if tab.panes.count <= 1 {
                tab.splitTree = nil
            }

            // Release daemon fd
            if let daemon = daemonAdapter {
                Task { try? await daemon.release(paneId: paneToClose.id) }
            }
        }

        // Remove renderer
        paneRenderers.removeValue(forKey: paneToClose.id)

        ForgeLog.log("[app] Closed pane \(paneToClose.id)")
        updateRenderers()
        WorkspacePersistence.save(workspace: workspace, windowFrame: nil)
    }

    /// Remove the Nth leaf from the tree, collapsing its parent if only one child remains.
    private func removeLeafAt(node: SplitNode, targetLeaf: Int, currentLeaf: inout Int) -> SplitNode? {
        switch node {
        case .leaf:
            if currentLeaf == targetLeaf {
                currentLeaf += 1
                return nil // Remove this leaf
            }
            currentLeaf += 1
            return .leaf
        case .split(let dir, let children, let proportions):
            var newChildren: [SplitNode] = []
            var newProportions: [CGFloat] = []
            for (i, child) in children.enumerated() {
                if let kept = removeLeafAt(node: child, targetLeaf: targetLeaf, currentLeaf: &currentLeaf) {
                    newChildren.append(kept)
                    if i < proportions.count { newProportions.append(proportions[i]) }
                }
            }
            if newChildren.count <= 1 {
                return newChildren.first ?? .leaf
            }
            // Renormalize proportions
            let sum = newProportions.reduce(0, +)
            if sum > 0 { newProportions = newProportions.map { $0 / sum } }
            return .split(dir, newChildren, proportions: newProportions)
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
        if config.isNativePTY {
            splitPaneNativePTY(direction: direction)
            return
        }
        guard let tabId = workspace.activeTabId else { return }
        Task { await tmux.splitWindow(id: tabId, direction: direction) }
    }

    private func splitPaneNativePTY(direction: SplitDirection) {
        guard let project = workspace.activeProject,
              let tabId = workspace.activeTabId,
              let tab = project.tabs.first(where: { $0.id == tabId })
        else { return }

        let paneId = UUID().uuidString
        let cwd = project.path ?? NSHomeDirectory()
        let pane = Pane(id: paneId, tabId: tabId, currentPath: cwd)

        // Find which pane was last focused (clicked). Can't use firstResponder
        // because clicking a toolbar button moves focus away from the terminal.
        let activePaneIndex: Int = {
            if let focusedId = lastFocusedPaneId,
               let idx = tab.panes.firstIndex(where: { $0.id == focusedId }) {
                return idx
            }
            // Fall back to last pane
            return max(tab.panes.count - 1, 0)
        }()

        // Insert after the active pane
        tab.panes.insert(pane, at: activePaneIndex + 1)

        // Update split tree: replace the active leaf with a split(direction, [leaf, leaf])
        if let existing = tab.splitTree {
            var leafIndex = 0
            tab.splitTree = splitLeafAt(node: existing, targetLeaf: activePaneIndex,
                                         currentLeaf: &leafIndex, direction: direction)
        } else {
            tab.splitTree = .split(direction, [.leaf, .leaf], proportions: [0.5, 0.5])
        }

        ForgeLog.log("[app] Split \(direction) at pane[\(activePaneIndex)] → \(paneId) (tree: \(tab.splitTree?.leafCount ?? 0) leaves, panes: \(tab.panes.count))")
        updateRenderers()
        WorkspacePersistence.save(workspace: workspace, windowFrame: nil)
    }

    /// Recursively find the Nth leaf in the tree and replace it with a split.
    private func splitLeafAt(node: SplitNode, targetLeaf: Int,
                              currentLeaf: inout Int, direction: SplitDirection) -> SplitNode {
        switch node {
        case .leaf:
            if currentLeaf == targetLeaf {
                currentLeaf += 1
                return .split(direction, [.leaf, .leaf], proportions: [0.5, 0.5])
            }
            currentLeaf += 1
            return .leaf
        case .split(let dir, let children, let proportions):
            let newChildren = children.map { child in
                splitLeafAt(node: child, targetLeaf: targetLeaf,
                           currentLeaf: &currentLeaf, direction: direction)
            }
            return .split(dir, newChildren, proportions: proportions)
        }
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

    func swapProject(offset: Int) {
        guard let activeId = workspace.activeProjectId,
              let fromIndex = workspace.projects.firstIndex(where: { $0.id == activeId })
        else { return }
        let toIndex = fromIndex + offset
        guard toIndex >= 0, toIndex < workspace.projects.count else { return }
        workspace.projects.swapAt(fromIndex, toIndex)
    }

    // MARK: - Notifications

    func toggleNotifications() {
        guard let attention = attentionManager,
              let project = workspace.activeProject,
              let tabId = workspace.activeTabId,
              let tab = project.tabs.first(where: { $0.id == tabId })
        else { return }
        if attention.isHidden(tab.uuid) {
            attention.unhide(tab.uuid)
        } else {
            attention.hide(tab.uuid)
        }
    }

    // MARK: - Attention

    func sendAttentionNotification(tabUUID: UUID) {
        guard config.config.notifications?.enabled == true, let notifier else { return }

        // In stack mode, suppress notifications unless explicitly enabled
        if config.isStackMode && !(config.config.stackView?.notifyInStackMode ?? false) { return }

        let notifications = config.config.notifications
        let sound = notifications?.sound
        let isActiveTab = workspace.findTab(byUUID: tabUUID).map { $0.tab.id == workspace.activeTabId } ?? false

        if isActiveTab {
            let showBanner = notifications?.activeTabBanner ?? false
            let playSound = notifications?.activeTabSound ?? true
            if showBanner {
                Task { await notifier.send(title: "Terminal needs attention", body: "A terminal is waiting for input", sound: sound, tabUUID: tabUUID) }
            } else if playSound {
                MacNotificationAdapter(toastState: toastState).playSound(sound)
            }
        } else {
            Task { await notifier.send(title: "Terminal needs attention", body: "A terminal is waiting for input", sound: sound, tabUUID: tabUUID) }
        }
    }

    private func clearAttention(tab: Tab) {
        for pane in tab.panes {
            pane.hasBell = false
            pane.hasContentMatch = false
        }
        Task { await tmux.clearBellFlag(tabId: tab.id) }
    }

    // MARK: - Session Restore

    private func restoreSession(name: String, path: String, adapter: TmuxAdapter) async {
        let canonical = URL(fileURLWithPath: path).standardized.path
        guard let snapshot = SessionSnapshotStore.load(path: canonical),
              !snapshot.tabs.isEmpty else { return }

        ForgeLog.log("[app] Restoring \(snapshot.tabs.count) tabs for \(name)")

        for (i, tab) in snapshot.tabs.enumerated() {
            let windowTarget: String
            if i == 0 {
                await adapter.renameWindow(target: "\(name):0", name: tab.name)
                windowTarget = "\(name):0"
            } else {
                let firstDir = tab.panes.first?.directory ?? path
                guard let windowId = await adapter.restoreTab(session: name, name: tab.name, directory: firstDir) else {
                    ForgeLog.log("[app] Failed to restore tab \(tab.name)")
                    continue
                }
                windowTarget = windowId
            }

            if tab.panes.count > 1, let layout = tab.layout {
                let tree = LayoutParser.parse(layout)
                let existingPaneIds = await adapter.listPaneIds(window: windowTarget)
                guard let firstPaneId = existingPaneIds.first else { continue }

                var leafPaneIds: [String] = []
                await collectLeafPanes(tree: tree, adapter: adapter, currentPaneId: firstPaneId, leafPaneIds: &leafPaneIds)

                await adapter.applyLayout(windowId: windowTarget, layout: layout)

                for (j, pane) in tab.panes.enumerated() where j < leafPaneIds.count {
                    if pane.directory != path {
                        await adapter.sendKeys(paneId: leafPaneIds[j], keys: "cd \(quoteForShell(pane.directory))")
                    }
                }
            } else if let pane = tab.panes.first, i == 0, pane.directory != path {
                if let paneId = (await adapter.listPaneIds(window: windowTarget)).first {
                    await adapter.sendKeys(paneId: paneId, keys: "cd \(quoteForShell(pane.directory))")
                }
            }
        }

        SessionSnapshotStore.delete(path: canonical)
        ForgeLog.log("[app] Restored session snapshot for \(name)")
    }

    private func collectLeafPanes(
        tree: SplitNode, adapter: TmuxAdapter,
        currentPaneId: String, leafPaneIds: inout [String]
    ) async {
        switch tree {
        case .leaf:
            leafPaneIds.append(currentPaneId)
        case .split(let direction, let children, _):
            var childPaneIds = [currentPaneId]
            for _ in children.dropFirst() {
                if let newId = await adapter.restoreSplit(targetPane: currentPaneId, direction: direction) {
                    childPaneIds.append(newId)
                }
            }
            for (i, child) in children.enumerated() where i < childPaneIds.count {
                await collectLeafPanes(tree: child, adapter: adapter, currentPaneId: childPaneIds[i], leafPaneIds: &leafPaneIds)
            }
        }
    }

    private func quoteForShell(_ s: String) -> String {
        "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
