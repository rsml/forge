import SwiftUI
import ForgeCore

/// Three-dots menu shared between Full and Slim chrome. Items both trigger the
/// browser action and display the keyboard shortcut alongside, so the menu
/// serves as both a launcher and a discoverable shortcut reference.
///
/// The Close item label is dynamic: "Close Tab" when this is the only pane in
/// its tab (closing it closes the whole tab), else "Close Pane". This mirrors
/// the convention used in `PaneContextMenu`.
struct BrowserChromeMenu: View {
    @Environment(AppState.self) private var appState
    @Environment(WorkspaceController.self) private var controller

    let pane: Pane
    let renderer: any BrowserRenderer

    var body: some View {
        Menu {
            Button("Focus URL  ⌘L") {
                appState.openURLPalette(for: pane)
            }

            Button("Reload  ⌘R") {
                renderer.reload()
            }

            Divider()

            Button("Back  ⌘[") {
                renderer.goBack()
            }
            .disabled(!(pane.browserState?.canGoBack ?? false))

            Button("Forward  ⌘]") {
                renderer.goForward()
            }
            .disabled(!(pane.browserState?.canGoForward ?? false))

            Divider()

            Button("Find in Page  ⌘F") {
                appState.openFind(for: pane.id)
            }

            Button("Web Inspector  ⌘⌥I") {
                renderer.toggleDevTools()
            }

            Divider()

            Button(closeLabel, role: .destructive) { closeAction() }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
    }

    /// "Close Pane" when this pane is one of several in its tab; otherwise
    /// "Close Tab" (single pane → closing it closes the whole tab). Falls back
    /// to "Close Tab" if the pane has already been removed from the workspace.
    private var closeLabel: String {
        guard let (_, tab, _) = controller.workspace.findPane(byId: pane.id) else {
            return "Close Tab"
        }
        return tab.panes.count > 1 ? "Close Pane" : "Close Tab"
    }

    private func closeAction() {
        guard let (project, tab, _) = controller.workspace.findPane(byId: pane.id) else {
            return
        }
        if tab.panes.count > 1 {
            controller.closePane(pane.id)
        } else {
            controller.removeTab(tab, in: project)
        }
    }
}
