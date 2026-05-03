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
                        set: { newValue in
                            if newValue {
                                expandedSessions.insert(session.id)
                            } else {
                                expandedSessions.remove(session.id)
                            }
                        }
                    )
                )
                .tag(session.id)
                .contextMenu {
                    Button("Rename...") {}
                    Divider()
                    Button("New Window") {
                        controller.addWindow(in: session)
                    }
                    Divider()
                    Button("Close Session", role: .destructive) {
                        controller.removeSession(session)
                    }
                }
            }
            .onMove { source, destination in
                controller.workspace.sessions.move(fromOffsets: source, toOffset: destination)
            }
        }
        .listStyle(.sidebar)
        .safeAreaInset(edge: .bottom) {
            HStack {
                Button {
                    showNewProject = true
                } label: {
                    Label("New Project", systemImage: "plus")
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                Spacer()
            }
            .background(.bar)
        }
        .sheet(isPresented: $showNewProject) {
            ProjectPickerView()
        }
        .navigationTitle("Forge")
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
