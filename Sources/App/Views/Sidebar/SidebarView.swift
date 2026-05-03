import SwiftUI

struct SidebarView: View {
    @Environment(WorkspaceController.self) var controller
    @State private var expandedSessions: Set<String> = []
    @State private var showNewProject = false
    @State private var selection: String?

    var body: some View {
        List(selection: $selection) {
            ForEach(controller.workspace.sessions) { session in
                SessionRow(
                    session: session,
                    isExpanded: Binding(
                        get: { expandedSessions.contains(session.id) },
                        set: { if $0 { expandedSessions.insert(session.id) } else { expandedSessions.remove(session.id) } }
                    ),
                    onSelectWindow: { window in
                        controller.selectSession(session)
                        controller.selectWindow(window)
                    }
                )
                .tag(session.id)
                .contextMenu {
                    Button("Rename...") {}
                    Divider()
                    Button("New Window") { controller.addWindow(in: session) }
                    Divider()
                    Button("Close Session", role: .destructive) { controller.removeSession(session) }
                }
            }
            .onMove { source, destination in
                controller.workspace.sessions.move(fromOffsets: source, toOffset: destination)
            }
        }
        .listStyle(.sidebar)
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button { showNewProject = true } label: {
                    Image(systemName: "plus")
                }
                .help("New Project")
            }
        }
        .sheet(isPresented: $showNewProject) {
            ProjectPickerView()
        }
        .onChange(of: selection) { _, newId in
            if let newId, let session = controller.workspace.session(byId: newId) {
                controller.selectSession(session)
            }
        }
        .onChange(of: controller.workspace.activeSessionId) { _, newId in
            selection = newId
        }
        .onAppear {
            selection = controller.workspace.activeSessionId
        }
    }
}
