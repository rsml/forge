import SwiftUI
import ForgeCore

struct TerminalArea: View {
    var project: Project
    @Environment(WorkspaceController.self) private var controller
    @Environment(ForgeConfigStore.self) private var configStore

    var body: some View {
        if let tab = project.tabs.first(where: { $0.id == controller.workspace.activeTabId }),
           !controller.paneRenderers.isEmpty {
            nativeTerminal(tab: tab)
        } else {
            Color(red: 0.1, green: 0.1, blue: 0.1)
                .ignoresSafeArea(edges: [.bottom, .trailing])
        }
    }

    @ViewBuilder
    private func nativeTerminal(tab: ForgeCore.Tab) -> some View {
        Group {
            if tab.panes.count > 1 {
                let tree: SplitNode = tab.splitTree ?? .split(
                    .vertical,
                    [SplitNode](repeating: .leaf, count: tab.panes.count),
                    proportions: [CGFloat](repeating: 1.0 / CGFloat(tab.panes.count), count: tab.panes.count)
                )
                PaneSplitView(node: tree, panes: tab.panes[...], renderers: controller.paneRenderers)
            } else if let pane = tab.panes.first {
                if pane.kind == .browser,
                   let renderer = controller.paneRenderers[pane.id] as? any BrowserRenderer {
                    BrowserPaneView(pane: pane, renderer: renderer).id(pane.id)
                } else if let renderer = controller.paneRenderers[pane.id] as? any TerminalRenderer {
                    // Context menu is attached via AppKit's `NSView.menu` inside
                    // PaneTerminalView. SwiftUI's `.contextMenu` doesn't fire
                    // here — GhosttyNSView intercepts right-click events.
                    PaneTerminalView(renderer: renderer, pane: pane)
                        .id(pane.id)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .ignoresSafeArea(edges: [.bottom, .trailing])
        .background(configStore.resolvedTheme?.background.color ?? Color(red: 0.1, green: 0.1, blue: 0.1))
        .background(
            GeometryReader { geo in
                Color.clear.onChange(of: geo.size) { _, size in
                    controller.terminalAreaSize = size
                }
                .onAppear { controller.terminalAreaSize = geo.size }
            }
        )
    }
}
