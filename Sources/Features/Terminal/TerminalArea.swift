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
        if tab.panes.count > 1, let layout = tab.layout {
            // Multi-pane: parse layout tree and render split view
            let tree = LayoutParser.parse(layout)
            PaneSplitView(node: tree, panes: tab.panes[...], renderers: controller.paneRenderers)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .ignoresSafeArea(edges: [.bottom, .trailing])
                .background(Color(red: 0.1, green: 0.1, blue: 0.1))
        } else if let pane = tab.panes.first, let renderer = controller.paneRenderers[pane.id] {
            // Single pane: direct render
            PaneTerminalView(renderer: renderer)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .ignoresSafeArea(edges: [.bottom, .trailing])
                .id(pane.id)
                .background(Color(red: 0.1, green: 0.1, blue: 0.1))
        }
    }
}
