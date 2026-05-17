import SwiftUI
import ForgeCore

struct TerminalArea: View {
    var project: Project
    @Environment(WorkspaceController.self) private var controller
    @Environment(ForgeConfigStore.self) private var configStore

    var body: some View {
        if configStore.isNativePaneRendering, !controller.paneRenderers.isEmpty,
           let tab = project.tabs.first(where: { $0.id == controller.workspace.activeTabId }) {
            nativeTerminal(tab: tab)
        } else {
            ForgeTerminalView(sessionName: project.name)
                .padding(.trailing, -15)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .ignoresSafeArea(edges: [.bottom, .trailing])
                .id(project.id)
                .background(Color(red: 0.1, green: 0.1, blue: 0.1))
        }
    }

    @ViewBuilder
    private func nativeTerminal(tab: ForgeCore.Tab) -> some View {
        Group {
            if tab.panes.count > 1 {
                let tree: SplitNode = if let layout = tab.layout {
                    LayoutParser.parse(layout)
                } else {
                    .split(.vertical,
                           [SplitNode](repeating: .leaf, count: tab.panes.count),
                           proportions: [CGFloat](repeating: 1.0 / CGFloat(tab.panes.count), count: tab.panes.count))
                }
                PaneSplitView(node: tree, panes: tab.panes[...], renderers: controller.paneRenderers)
            } else if let pane = tab.panes.first, let renderer = controller.paneRenderers[pane.id] {
                PaneTerminalView(renderer: renderer).id(pane.id)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .ignoresSafeArea(edges: [.bottom, .trailing])
        .background(Color(red: 0.1, green: 0.1, blue: 0.1))
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
