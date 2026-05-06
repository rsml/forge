import SwiftUI
import ForgeDomain

struct SidebarProjectList: View {
    var position: String = "left"
    var onToggleSidebar: () -> Void = {}
    @Environment(WorkspaceController.self) var controller
    @State private var expandedSessions: Set<String> = []
    @State private var renamingSessionId: String?
    @State private var renamingWindowId: String?
    @State private var renameText = ""

    var body: some View {
        let tabBarPos = ForgeConfigStore.shared.config.general?.tabBarPosition ??
                        ForgeConfigStore.shared.config.terminal?.tabBarPosition ?? "top"
        let toolbarOnBottom = tabBarPos == "bottom"

        VStack(spacing: 0) {
            NotificationCenterRow(position: position)

            if !toolbarOnBottom {
                toolbarRow
            }

            projectList

            if toolbarOnBottom {
                toolbarRow
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
        .onReceive(NotificationCenter.default.publisher(for: .forgeRenameProject)) { _ in
            guard let session = controller.workspace.activeSession else { return }
            renamingWindowId = nil
            renameText = session.name
            renamingSessionId = session.id
        }
    }

    @ViewBuilder
    private var toolbarRow: some View {
        HStack(spacing: 0) {
            if position == "right" {
                IconButton(systemName: "sidebar.right") { onToggleSidebar() }
                    .help(KeyboardShortcuts.toggleSidebar.tooltip)
                IconButton(systemName: "command") {
                    NotificationCenter.default.post(name: .forgeCommandPalette, object: nil)
                }
                .help(KeyboardShortcuts.commandPalette.tooltip)
                IconButton(systemName: "plus") {
                    NotificationCenter.default.post(name: .forgeNewProject, object: nil)
                }
                .help(KeyboardShortcuts.newProject.tooltip)
            } else {
                IconButton(systemName: "plus") {
                    NotificationCenter.default.post(name: .forgeNewProject, object: nil)
                }
                .help(KeyboardShortcuts.newProject.tooltip)
                IconButton(systemName: "command") {
                    NotificationCenter.default.post(name: .forgeCommandPalette, object: nil)
                }
                .help(KeyboardShortcuts.commandPalette.tooltip)
                IconButton(systemName: "sidebar.left") { onToggleSidebar() }
                    .help(KeyboardShortcuts.toggleSidebar.tooltip)
            }
        }
        .frame(height: ForgeConfigStore.shared.titlebarHeight)
    }

    @ViewBuilder
    private var projectList: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 2) {
                ReorderableStack(controller.workspace.sessions, axis: .vertical, spacing: 2) { session, isDragging in
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
                        onRenameCancel: { renamingSessionId = nil },
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
                        onRenameWindowCancel: { renamingWindowId = nil },
                        projectIndex: controller.workspace.sessions.firstIndex(where: { $0.id == session.id }).map { $0 + 1 } ?? 0
                    )
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
                } onReorder: { from, to in
                    controller.workspace.sessions.move(fromOffsets: IndexSet(integer: from), toOffset: to)
                }
            }
            .padding(.horizontal, 0)
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
        .onTapGesture(count: 2) {
            NotificationCenter.default.post(name: .forgeNewProject, object: nil)
        }
    }
}
