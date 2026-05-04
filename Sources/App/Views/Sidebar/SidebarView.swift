import SwiftUI

struct SidebarView: View {
    var onToggleSidebar: () -> Void = {}
    @Environment(WorkspaceController.self) var controller
    @State private var expandedSessions: Set<String> = []
    @State private var renamingSessionId: String?
    @State private var renamingWindowId: String?
    @State private var renameText = ""
    @State private var draggedSessionId: String?

    var body: some View {
        VStack(spacing: 0) {
            // Title bar zone — traffic lights live here; not interactive
            Color.clear.frame(height: 28)

            // Sidebar toolbar — each button fills half the row for maximum tap area
            HStack(spacing: 0) {
                IconButton(systemName: "plus") {
                    NotificationCenter.default.post(name: .forgeNewProject, object: nil)
                }
                    .help(KeyboardShortcuts.newProject.tooltip)

                IconButton(systemName: "bell") {
                    NotificationCenter.default.post(name: .forgeNotifications, object: nil)
                }
                    .help(KeyboardShortcuts.notifications.tooltip)
                    .overlay(alignment: .topTrailing) {
                        if controller.workspace.sessions.contains(where: { $0.needsAttention }) {
                            Circle()
                                .fill(Color.accentColor)
                                .frame(width: 6, height: 6)
                                .offset(x: -6, y: 6)
                        }
                    }

                IconButton(systemName: "command") {
                    NotificationCenter.default.post(name: .forgeCommandPalette, object: nil)
                }
                .help(KeyboardShortcuts.commandPalette.tooltip)

                IconButton(systemName: "sidebar.left") { onToggleSidebar() }
                    .help(KeyboardShortcuts.toggleSidebar.tooltip)
            }
            .frame(height: 28)

            // Project list
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    ForEach(Array(controller.workspace.sessions.enumerated()), id: \.element.id) { index, session in
                        SessionRow(
                            session: session,
                            isActive: session.id == controller.workspace.activeSessionId,
                            activeWindowId: controller.workspace.activeWindowId,
                            isExpanded: Binding(
                                get: { expandedSessions.contains(session.id) },
                                set: {
                                    if $0 { expandedSessions.insert(session.id) } else { expandedSessions.remove(session.id) }
                                    let names = controller.workspace.sessions
                                        .filter { expandedSessions.contains($0.id) }
                                        .map(\.name)
                                    controller.saveUIState(expandedSessionNames: names)
                                }
                            ),
                            isRenaming: renamingSessionId == session.id,
                            renameText: $renameText,
                            onRenameCommit: {
                                if !renameText.isEmpty {
                                    session.name = renameText // Optimistic update
                                    controller.renameSession(session, to: renameText)
                                }
                                renamingSessionId = nil
                            },
                            onSelect: {
                                controller.selectSession(session)
                            },
                            onSelectWindow: { window in
                                controller.selectSession(session)
                                controller.selectWindow(window)
                            },
                            renamingWindowId: renamingWindowId,
                            onStartWindowRename: { window in
                                renamingSessionId = nil
                                renamingWindowId = window.id
                                renameText = window.name
                            },
                            onRenameWindowCommit: {
                                if !renameText.isEmpty,
                                   let window = session.windows.first(where: { $0.id == renamingWindowId }) {
                                    window.name = renameText // Optimistic update
                                    controller.renameWindow(window, to: renameText)
                                }
                                renamingWindowId = nil
                            },
                            projectIndex: index + 1
                        )
                        .opacity(draggedSessionId == session.id ? 0.0 : 1.0)
                        .onDrag {
                            draggedSessionId = session.id
                            return NSItemProvider(object: session.id as NSString)
                        }
                        .onDrop(of: [.text], delegate: ReorderDropDelegate(
                            item: session,
                            items: controller.workspace.sessions,
                            draggedItemId: $draggedSessionId,
                            onMove: { from, to in
                                controller.workspace.sessions.move(fromOffsets: from, toOffset: to)
                            }
                        ))
                        .contextMenu {
                            Button("Rename...") {
                                renamingWindowId = nil
                                renameText = session.name
                                renamingSessionId = session.id
                            }
                            Divider()
                            Button("New Tab") { controller.addWindow(in: session) }
                            Divider()
                            Button("Close Project", role: .destructive) { controller.removeSession(session) }
                        }
                    }
                }
                .padding(.horizontal, 6)
                .padding(.top, 4)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
            .onTapGesture(count: 2) {
                NotificationCenter.default.post(name: .forgeNewProject, object: nil)
            }
        }
        .onAppear {
            // Restore expanded sessions from saved state
            if let names = ForgeConfig.load().uiState?.expandedSessionNames {
                let nameSet = Set(names)
                expandedSessions = Set(controller.workspace.sessions
                    .filter { nameSet.contains($0.name) }
                    .map(\.id))
            }
        }
    }
}
