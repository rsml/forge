import SwiftUI
import ForgeCore

struct TerminalArea: View {
    var project: Project
    @Environment(WorkspaceController.self) private var controller
    @Environment(ForgeConfigStore.self) private var configStore

    var body: some View {
        if configStore.isNativePaneRendering, !controller.paneRenderers.isEmpty,
           let tab = project.tabs.first(where: { $0.id == controller.workspace.activeTabId }) {
            if let firstPaneId = tab.panes.first?.id,
               let renderer = controller.paneRenderers[firstPaneId] {
                // Temporary: single-pane view. Step 4 replaces with PaneSplitView.
                PaneTerminalView(renderer: renderer)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .ignoresSafeArea(edges: [.bottom, .trailing])
                    .id(firstPaneId)
                    .border(Color.blue.opacity(0.5), width: 1) // DEBUG
                    .background(Color(red: 0.1, green: 0.1, blue: 0.1))
            }
        } else {
            // Legacy path: tmux attach rendered by SwiftTerm LocalProcessTerminalView
            ForgeTerminalView(sessionName: project.name)
                .padding(.trailing, -15) // Compensate for SwiftTerm's reserved legacy scroller width
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .ignoresSafeArea(edges: [.bottom, .trailing])
                .id(project.id)
                .background(Color(red: 0.1, green: 0.1, blue: 0.1))
        }
    }
}
