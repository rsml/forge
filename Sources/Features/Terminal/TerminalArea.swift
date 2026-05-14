import SwiftUI
import ForgeCore

struct TerminalArea: View {
    var project: Project
    @Environment(WorkspaceController.self) private var controller
    @Environment(ForgeConfigStore.self) private var configStore

    var body: some View {
        if configStore.isNativePaneRendering, let renderer = controller.activeRenderer {
            PaneTerminalView(renderer: renderer)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .ignoresSafeArea(edges: [.bottom, .trailing])
                .id(renderer.view) // recreate when renderer changes
                .background(Color(red: 0.1, green: 0.1, blue: 0.1))
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
