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
        } else if let tab = project.tabs.first(where: { $0.active }) ?? project.tabs.first {
            workspace.activeTabId = tab.id
        }

        saveUIState()
        updateRenderers()
    }

    func selectTab(_ tab: Tab) {
        workspace.activeTabId = tab.id
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
        saveUIState()
        updateRenderers()
    }

    func addProject(name: String, path: String) async {
        addProjectNativePTY(name: name, path: path)
    }

    private func addProjectNativePTY(name: String, path: String) {
        let projectId = UUID().uuidString
        let project = Project(id: projectId, name: name, path: path)
        let tabId = UUID().uuidString
        let tab = Tab(id: tabId, projectId: projectId, index: 0, name: "zsh")
        let paneId = UUID().uuidString
        let pane = Pane(id: paneId, tabId: tabId, currentPath: path)
        tab.panes.append(pane)
        project.tabs.append(tab)
        workspace.projects.append(project)
        // Create renderer BEFORE selectProject triggers SwiftUI render — prevents flash
        let renderer = createExecRenderer(for: pane, cwd: path)
        paneRenderers[paneId] = renderer
        scheduleDaemonRegister(paneId: paneId, cwd: path)
        selectProject(project)
        ForgeLog.log("[app] Added project \(name) (native PTY)")
    }

    func removeProject(_ project: Project) async {
        ForgeLog.log("[app] Removing project: \(project.name)")

        guard await confirmClose(target: .project(project)) else { return }
        await removeProjectAfterConfirm(project)
    }

    /// Unified close-confirmation gate. Pass the target *that the user requested*
    /// — `.pane` for cmd+W, `.tab` for tab X, `.project` for project X. Each
    /// level consults its own setting (`confirmClosePane` / `confirmCloseTab` /
    /// `confirmCloseProject`). No cascade-based target picking — the prompt
    /// always speaks at the user's action level.
    ///
    /// Returns true if the close should proceed (no prompt needed, or user
    /// confirmed). Returns false if the user cancelled.
    @MainActor
    private func confirmClose(target: CloseConfirmation.CloseTarget) async -> Bool {
        let general = config.config.general
        let paneMode = CloseConfirmation.TabConfirmMode(rawValue: general?.confirmClosePane ?? "")
            ?? .whenActive
        let tabMode = CloseConfirmation.TabConfirmMode(rawValue: general?.confirmCloseTab ?? "")
            ?? .whenActive
        let projectMode = CloseConfirmation.TabConfirmMode(rawValue: general?.confirmCloseProject ?? "")
            ?? .whenActive

        let scopedPaneIds: [String]
        switch target {
        case .pane(let id):
            scopedPaneIds = [id]
        case .tab(let tab, _):
            scopedPaneIds = tab.panes.map(\.id)
        case .project(let project):
            scopedPaneIds = project.tabs.flatMap { $0.panes.map(\.id) }
        }

        let activities: [PaneActivity] = await {
            if let port = activityPort { return await port.query(paneIds: scopedPaneIds) }
            return []
        }()

        let decision = CloseConfirmation.evaluate(
            target: target,
            activities: activities,
            confirmClosePane: paneMode,
            confirmCloseTab: tabMode,
            confirmCloseProject: projectMode
        )

        if let alert = decision.alert {
            guard let window = NSApp.mainWindow else { return true }
            return await CloseConfirmation.present(alert, in: window)
        }
        return true
    }

    private func removeProjectNativePTY(_ project: Project) {
        // Release daemon fds and remove renderers for all panes
        for tab in project.tabs {
            for pane in tab.panes {
                paneRenderers.removeValue(forKey: pane.id)
                paneActivityWatcher?.paneRemoved(pane.id)
                if let daemon = daemonAdapter {
                    Task { try? await daemon.release(paneId: pane.id) }
                }
            }
        }

        // Switch to another project before removing
        if let index = workspace.projects.firstIndex(where: { $0.id == project.id }) {
            let nextIndex = index > 0 ? index - 1 : min(1, workspace.projects.count - 1)
            if nextIndex != index, nextIndex < workspace.projects.count {
                selectProject(workspace.projects[nextIndex])
            }
        }

        // Remove from model
        workspace.projects.removeAll { $0.id == project.id }

        // Handle empty workspace
        if workspace.projects.isEmpty {
            workspace.activeProjectId = nil
            workspace.activeTabId = nil
            paneRenderers.removeAll()
        }

        // Persist immediately
        let frame = NSApp.mainWindow?.frame
        WorkspacePersistence.save(workspace: workspace, windowFrame: frame)
        ForgeLog.log("[app] Removed project \(project.name) (native PTY)")
    }

    func addTab(in project: Project) {
        ForgeLog.log("[app] Adding tab in project: \(project.name)")
        addTabNativePTY(in: project)
    }

    private func addTabNativePTY(in project: Project) {
        let tabId = UUID().uuidString
        let tab = Tab(id: tabId, projectId: project.id, index: project.tabs.count, name: "zsh")
        let paneId = UUID().uuidString
        let cwd = project.path ?? NSHomeDirectory()
        let pane = Pane(id: paneId, tabId: tabId, currentPath: cwd)
        tab.panes.append(pane)
        project.tabs.append(tab)
        // Create renderer BEFORE selectTab triggers SwiftUI render — prevents flash
        let renderer = createExecRenderer(for: pane, cwd: cwd)
        paneRenderers[paneId] = renderer
        scheduleDaemonRegister(paneId: paneId, cwd: cwd)
        selectTab(tab)
        ForgeLog.log("[app] Added tab in \(project.name) (native PTY)")
    }

    func removeTab(_ tab: Tab) {
        guard let project = workspace.activeProject else { return }
        removeTab(tab, in: project)
    }

    func removeTab(_ tab: Tab, in project: Project) {
        ForgeLog.log("[app] Removing tab: \(tab.name) from \(project.name)")
        Task { @MainActor in
            guard await confirmClose(target: .tab(tab, in: project)) else { return }
            performRemoveTab(tab, in: project)
        }
    }

    /// Inner removeTab path — no confirmation (caller already prompted).
    @MainActor
    private func performRemoveTab(_ tab: Tab, in project: Project) {
        removeTabNativePTY(tab, in: project)
    }

    /// Project close path that skips re-prompting (caller already confirmed via
    /// `evaluateClose` which resolved to `.project`).
    @MainActor
    private func removeProjectAfterConfirm(_ project: Project) async {
        ForgeLog.log("[app] Removing project: \(project.name) (post-confirm)")
        removeProjectNativePTY(project)
    }

    private func removeTabNativePTY(_ tab: Tab, in project: Project?) {
        guard let project else { return }
        // Release daemon fds for all panes in this tab
        for pane in tab.panes {
            paneRenderers.removeValue(forKey: pane.id)
            paneActivityWatcher?.paneRemoved(pane.id)
            if let daemon = daemonAdapter {
                Task { try? await daemon.release(paneId: pane.id) }
            }
        }
        // Pick neighbor before removing
        let neighborTab: Tab? = {
            guard let index = project.tabs.firstIndex(where: { $0.id == tab.id }) else { return nil }
            let nextIndex = index > 0 ? index - 1 : min(index + 1, project.tabs.count - 1)
            guard nextIndex != index, nextIndex < project.tabs.count else { return nil }
            return project.tabs[nextIndex]
        }()
        project.tabs.removeAll { $0.id == tab.id }
        if let neighborTab {
            selectTab(neighborTab)
        } else if project.tabs.isEmpty {
            // Last tab removed — remove the project
            removeProjectNativePTY(project)
        }
        let frame = NSApp.mainWindow?.frame
        WorkspacePersistence.save(workspace: workspace, windowFrame: frame)
        ForgeLog.log("[app] Removed tab \(tab.name) (native PTY)")
    }

    func renameProject(_ project: Project, to name: String) {
        ForgeLog.log("[app] Renaming project: \(project.name) → \(name)")
        project.name = name
        let frame = NSApp.mainWindow?.frame
        WorkspacePersistence.save(workspace: workspace, windowFrame: frame)
    }

    func renameTab(_ tab: Tab, to name: String) {
        ForgeLog.log("[app] Renaming tab: \(tab.name) → \(name)")
        tab.name = name
        let frame = NSApp.mainWindow?.frame
        WorkspacePersistence.save(workspace: workspace, windowFrame: frame)
    }

    func closeCurrentPane() {
        Task { @MainActor in
            await closeCurrentPaneAsync()
        }
    }

    @MainActor
    private func closeCurrentPaneAsync() async {
        guard let project = workspace.activeProject,
              let tabId = workspace.activeTabId,
              let tab = project.tabs.first(where: { $0.id == tabId })
        else { return }

        // Pick the focused pane — set by GhosttyNSView.onFocusGained.
        let activePane: Pane? = {
            if let focusedId = lastFocusedPaneId,
               let p = tab.panes.first(where: { $0.id == focusedId }) {
                return p
            }
            return tab.panes.last
        }()
        guard let pane = activePane else { return }

        guard await confirmClose(target: .pane(id: pane.id)) else { return }

        performClosePaneNativePTY(paneId: pane.id, in: tab, project: project)
    }

    /// Pane-close worker for native PTY. No confirmation (caller already prompted).
    @MainActor
    private func performClosePaneNativePTY(paneId: String, in tab: Tab, project: Project) {
        guard let paneIndex = tab.panes.firstIndex(where: { $0.id == paneId }) else { return }
        let paneToClose = tab.panes[paneIndex]

        // Last pane → cascade to tab close (which cascades to project if needed)
        if tab.panes.count <= 1 {
            removeTabNativePTY(tab, in: project)
            return
        }

        tab.panes.remove(at: paneIndex)
        if let tree = tab.splitTree {
            var leafIndex = 0
            tab.splitTree = removeLeafAt(node: tree, targetLeaf: paneIndex, currentLeaf: &leafIndex)
        }
        if tab.panes.count <= 1 {
            tab.splitTree = nil
        }

        paneRenderers.removeValue(forKey: paneToClose.id)
        paneActivityWatcher?.paneRemoved(paneToClose.id)
        if let daemon = daemonAdapter {
            Task { try? await daemon.release(paneId: paneToClose.id) }
        }
        ForgeLog.log("[app] Closed pane \(paneToClose.id)")
        updateRenderers()
        let frame = NSApp.mainWindow?.frame
        WorkspacePersistence.save(workspace: workspace, windowFrame: frame)
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

        source.tabs.removeAll { $0.id == tab.id }
        tab.projectId = target.id
        tab.index = target.tabs.count
        target.tabs.append(tab)
        let frame = NSApp.mainWindow?.frame
        WorkspacePersistence.save(workspace: workspace, windowFrame: frame)
    }

    func clearScrollback() {
        guard let paneId = workspace.activePaneId,
              let renderer = paneRenderers[paneId] as? GhosttyRenderer
        else { return }
        // Feed CSI 3 J (erase saved lines / scrollback), CSI 2 J (erase display),
        // CSI H (cursor home). Ghostty's emulator processes these as if they
        // arrived from the PTY — gives the user a clear screen + cleared
        // scrollback buffer.
        renderer.feed(Data([
            0x1B, 0x5B, 0x33, 0x4A,
            0x1B, 0x5B, 0x32, 0x4A,
            0x1B, 0x5B, 0x48,
        ]))
    }

    /// Currently focused pane, derived from `lastFocusedPaneId` (set on focus
    /// gain) with fallback to the active tab's first pane. Used by the
    /// right-click menu to decide the dynamic Convert label.
    var focusedPane: Pane? {
        guard let project = workspace.activeProject,
              let tabId = workspace.activeTabId,
              let tab = project.tabs.first(where: { $0.id == tabId })
        else { return nil }
        if let focusedId = lastFocusedPaneId,
           let p = tab.panes.first(where: { $0.id == focusedId }) {
            return p
        }
        return tab.panes.first
    }

    /// Convert the focused pane between terminal and browser. Routes to the
    /// kind-specific implementation in WorkspaceController+Browser.
    func convertFocusedPane() {
        guard let pane = focusedPane else { return }
        switch pane.kind {
        case .terminal: convertToBrowser(pane: pane)
        case .browser:  convertToTerminal(pane: pane)
        }
    }

    func splitPane(direction: SplitDirection, position: SplitPosition = .after, as kind: PaneKind = .terminal) {
        splitPaneNativePTY(direction: direction, position: position, as: kind)
    }

    func splitPaneNativePTY(
        direction: SplitDirection,
        position: SplitPosition = .after,
        as kind: PaneKind = .terminal
    ) {
        guard let project = workspace.activeProject,
              let tabId = workspace.activeTabId,
              let tab = project.tabs.first(where: { $0.id == tabId })
        else { return }

        let paneId = UUID().uuidString
        let cwd = project.path ?? NSHomeDirectory()

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

        // Construct the new pane based on kind. Terminal/browser differ ONLY in:
        //   (a) Pane factory, (b) renderer type, (c) no daemon register for browser,
        //   (d) no PTY spawn for browser. Tree mutation + persistence are identical.
        let pane: Pane
        switch kind {
        case .terminal:
            pane = Pane(id: paneId, tabId: tabId, currentPath: cwd)
        case .browser:
            pane = Pane.browser(id: paneId, tabId: tabId)
        }

        // Insert relative to the active pane. `.after` keeps existing behavior;
        // `.before` inserts at the active pane's slot, shifting it right/down.
        let insertIndex = position == .before ? activePaneIndex : activePaneIndex + 1
        tab.panes.insert(pane, at: insertIndex)

        // Update split tree: replace the active leaf with a split of two leaves.
        // Leaf order is fixed (`[.leaf, .leaf]`); the new pane's position relative
        // to the original is determined by `tab.panes` insertion above (the tree's
        // leaf-index walk maps positionally to `tab.panes`).
        if let existing = tab.splitTree {
            var leafIndex = 0
            tab.splitTree = splitLeafAt(node: existing, targetLeaf: activePaneIndex,
                                         currentLeaf: &leafIndex, direction: direction)
        } else {
            tab.splitTree = .split(direction, [.leaf, .leaf], proportions: [0.5, 0.5])
        }

        // Set focus to the NEW pane (so subsequent splits target it)
        lastFocusedPaneId = paneId

        // Create the renderer synchronously BEFORE the next SwiftUI render to avoid
        // a frame with no renderer for the new pane (flash). Mirrors the terminal
        // pattern in addTabNativePTY / addProjectNativePTY.
        switch kind {
        case .terminal:
            // Terminal path: let updateRenderers create the EXEC renderer +
            // schedule daemon register. Matches existing behavior.
            ForgeLog.log("[app] Split \(direction) \(position) at pane[\(activePaneIndex)] → \(paneId) (tree: \(tab.splitTree?.leafCount ?? 0) leaves, panes: \(tab.panes.count))")
            updateRenderers()
        case .browser:
            // Browser path: no PTY, no daemon. Create renderer + wire callbacks
            // directly, then let updateRenderers handle focus + persistence.
            let renderer = WebKitBrowserRenderer()
            wireBrowserCallbacks(renderer: renderer, pane: pane)
            paneRenderers[paneId] = renderer
            ForgeLog.log("[app] Split \(direction) \(position) (browser) at pane[\(activePaneIndex)] → \(paneId) (tree: \(tab.splitTree?.leafCount ?? 0) leaves, panes: \(tab.panes.count))")
            updateRenderers()
            // Auto-open the URL palette so the user can navigate immediately.
            appState?.openURLPalette(for: pane)
        }

        WorkspacePersistence.save(workspace: workspace, windowFrame: nil)

        // Make the new pane's view first responder (visual focus). Skip for
        // browser panes — the URL palette opened above (.openURLPalette) takes
        // focus; promoting the WKWebView here triggers a 300ms-late steal that
        // the palette has to fight via its repeated-assert loop.
        if kind == .terminal {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                guard let renderer = self?.paneRenderers[paneId] else { return }
                renderer.view.window?.makeFirstResponder(renderer.view)
            }
        }
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

    /// Close a specific pane by ID. Mirrors `closeCurrentPane` but targets the
    /// pane the user actually right-clicked (which may not be `lastFocusedPaneId`).
    /// Cascades to tab close if this is the only pane in its tab.
    func closePane(_ paneId: String) {
        Task { @MainActor in
            await closePaneAsync(paneId: paneId)
        }
    }

    @MainActor
    private func closePaneAsync(paneId: String) async {
        guard let (project, tab, _) = workspace.findPane(byId: paneId) else { return }
        guard await confirmClose(target: .pane(id: paneId)) else { return }

        performClosePaneNativePTY(paneId: paneId, in: tab, project: project)
    }

    func reorderTab(in project: Project, from: Int, to: Int) {
        guard from >= 0, from < project.tabs.count else { return }
        project.tabs.move(fromOffsets: IndexSet(integer: from), toOffset: to)
        let frame = NSApp.mainWindow?.frame
        WorkspacePersistence.save(workspace: workspace, windowFrame: frame)
    }

    func swapTab(offset: Int) {
        guard let project = workspace.activeProject,
              let tabId = workspace.activeTabId,
              let fromIndex = project.tabs.firstIndex(where: { $0.id == tabId })
        else { return }
        let toIndex = fromIndex + offset
        guard toIndex >= 0, toIndex < project.tabs.count else { return }
        project.tabs.swapAt(fromIndex, toIndex)
        let frame = NSApp.mainWindow?.frame
        WorkspacePersistence.save(workspace: workspace, windowFrame: frame)
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

    func clearAttention(tab: Tab) {
        for pane in tab.panes {
            pane.terminalState?.hasBell = false
            pane.terminalState?.hasContentMatch = false
        }
    }
}
