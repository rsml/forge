import SwiftUI
import ForgeCore

/// Shared menu body for the pane right-click menu and the tab right-click menu.
///
/// - On a pane surface (right-click in terminal/browser content): pass the pane.
///   Shows Convert + a dynamic close label ("Close Tab" iff it's the only pane,
///   else "Close Pane").
/// - On a tab surface (sidebar row, bottom tab bar): pass `pane: nil`.
///   Hides Convert; close always says "Close Tab".
struct PaneContextMenu: View {
    let controller: WorkspaceController
    let appState: AppState
    let attention: AttentionManager
    let project: Project
    let tab: ForgeCore.Tab
    /// Non-nil only for pane surfaces. nil for tab-row context menus.
    let pane: Pane?

    /// Convenience initializer for pane-surface call sites where only the pane is
    /// known. Looks up the owning project/tab via the controller and renders an
    /// empty group if the pane has already been removed.
    @ViewBuilder
    static func forPane(
        _ pane: Pane,
        controller: WorkspaceController,
        appState: AppState,
        attention: AttentionManager
    ) -> some View {
        if let (project, tab, _) = controller.workspace.findPane(byId: pane.id) {
            PaneContextMenu(
                controller: controller,
                appState: appState,
                attention: attention,
                project: project,
                tab: tab,
                pane: pane
            )
        } else {
            EmptyView()
        }
    }

    var body: some View {
        Group {
            Menu("Split right") {
                Button("As Terminal") { split(.horizontal, .after, .terminal) }
                Button("As Browser") { split(.horizontal, .after, .browser) }
            }
            Menu("Split down") {
                Button("As Terminal") { split(.vertical, .after, .terminal) }
                Button("As Browser") { split(.vertical, .after, .browser) }
            }
            Menu("Split left") {
                Button("As Terminal") { split(.horizontal, .before, .terminal) }
                Button("As Browser") { split(.horizontal, .before, .browser) }
            }
            Menu("Split up") {
                Button("As Terminal") { split(.vertical, .before, .terminal) }
                Button("As Browser") { split(.vertical, .before, .browser) }
            }

            Divider()

            Button("New Tab") { controller.addTab(in: project) }
                .keyboardShortcut(KeyboardShortcuts.newTab.key, modifiers: KeyboardShortcuts.newTab.modifiers)
            Button("New Browser Tab") { controller.addBrowserTab(in: project) }
                .keyboardShortcut("t", modifiers: [.command, .option])

            Divider()

            Button("Rename Tab") { appState.startTabRename(tab) }
                .keyboardShortcut(KeyboardShortcuts.renameTab.key, modifiers: KeyboardShortcuts.renameTab.modifiers)

            if let pane {
                Button(pane.kind == .browser ? "Convert to Terminal" : "Convert to Browser") {
                    switch pane.kind {
                    case .terminal: controller.convertToBrowser(pane: pane)
                    case .browser:  controller.convertToTerminal(pane: pane)
                    }
                }
            }

            Button(closeLabel, role: .destructive) { closeAction() }
                .keyboardShortcut(KeyboardShortcuts.closePane.key, modifiers: KeyboardShortcuts.closePane.modifiers)

            Divider()

            if attention.isHidden(tab.uuid) {
                Button("Enable Notifications") { attention.unhide(tab.uuid) }
                    .keyboardShortcut(KeyboardShortcuts.toggleNotifications.key, modifiers: KeyboardShortcuts.toggleNotifications.modifiers)
            } else {
                Button("Disable Notifications") { attention.hide(tab.uuid) }
                    .keyboardShortcut(KeyboardShortcuts.toggleNotifications.key, modifiers: KeyboardShortcuts.toggleNotifications.modifiers)
            }
        }
    }

    /// "Close Pane" when this pane is one of several in its tab; otherwise
    /// "Close Tab" (single pane → closing it closes the whole tab; tab-surface
    /// menus always close the whole tab).
    private var closeLabel: String {
        guard pane != nil else { return "Close Tab" }
        return tab.panes.count > 1 ? "Close Pane" : "Close Tab"
    }

    private func closeAction() {
        if let pane, tab.panes.count > 1 {
            controller.closePane(pane.id)
        } else {
            controller.removeTab(tab, in: project)
        }
    }

    /// Re-target the split to the right-clicked pane (if any) before invoking
    /// `splitPane` — which reads `lastFocusedPaneId` for placement. Without this,
    /// right-clicking a non-focused pane would split the focused pane instead.
    /// For tab-surface menus (pane == nil), preserve existing focus.
    private func split(_ direction: SplitDirection, _ position: SplitPosition, _ kind: PaneKind) {
        if let pane {
            controller.lastFocusedPaneId = pane.id
        }
        controller.splitPane(direction: direction, position: position, as: kind)
    }
}
