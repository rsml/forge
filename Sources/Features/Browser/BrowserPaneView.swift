import SwiftUI
import ForgeCore

/// SwiftUI host for a browser pane. Selects a chrome view based on the user's
/// `browserChromeType` setting (full / slim / none) and re-evaluates on every
/// body call, so existing browser panes restyle live when the setting changes.
/// Overlays the URL palette when `AppState.urlPalettePane` is this pane, and
/// the find-in-page bar when `AppState.findActivePane` is this pane.
struct BrowserPaneView: View {
    @Environment(AppState.self) private var appState
    @Environment(WorkspaceController.self) private var controller
    @Environment(ForgeConfigStore.self) private var configStore
    @Environment(AttentionManager.self) private var attention

    let pane: Pane
    let renderer: any BrowserRenderer

    var body: some View {
        ZStack {
            chromeForCurrentMode

            if appState.urlPalettePane?.id == pane.id,
               let tab = controller.workspace.findTab(byPaneId: pane.id)?.tab {
                BrowserURLPalette(
                    initialInput: pane.browserState?.url?.absoluteString ?? "",
                    suggestions: controller.detectedPortsForTab(tab),
                    onSubmit: { url in
                        renderer.loadURL(url)
                        appState.closeURLPalette()
                    },
                    onCancel: { appState.closeURLPalette() }
                )
                .transition(.scale(scale: 0.96).combined(with: .opacity))
            }

            if appState.findActivePane == pane.id {
                VStack {
                    BrowserFindBar(
                        pane: pane,
                        renderer: renderer,
                        onDismiss: { appState.closeFind() }
                    )
                    .padding(.top, 8)
                    Spacer()
                }
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.25, dampingFraction: 0.85),
                   value: appState.urlPalettePane?.id)
        .animation(.spring(response: 0.25, dampingFraction: 0.85),
                   value: appState.findActivePane)
        .contextMenu {
            PaneContextMenu.forPane(
                pane,
                controller: controller,
                appState: appState,
                attention: attention
            )
        }
    }

    @ViewBuilder
    private var chromeForCurrentMode: some View {
        switch configStore.config.general?.browserChromeType ?? "full" {
        case "full": BrowserChromeFull(pane: pane, renderer: renderer)
        case "slim": BrowserChromeSlim(pane: pane, renderer: renderer)
        default:     BrowserChromeNone(renderer: renderer)
        }
    }
}
