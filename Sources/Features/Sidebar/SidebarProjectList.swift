import SwiftUI
import ForgeCore

struct SidebarProjectList: View {
    @Environment(ForgeConfigStore.self) private var configStore
    var position: String = "left"
    var onToggleSidebar: () -> Void = {}
    @Environment(WorkspaceController.self) var controller
    @Environment(AppState.self) private var appState

    var body: some View {
        let tabBarPos = configStore.config.general?.tabBarPosition ??
                        configStore.config.terminal?.tabBarPosition ?? "top"
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
    }

    @ViewBuilder
    private var toolbarRow: some View {
        HStack(spacing: 0) {
            if position == "right" {
                IconButton(systemName: "sidebar.right") { onToggleSidebar() }
                    .tooltip(KeyboardShortcuts.toggleSidebar)
                IconButton(systemName: "command") {
                    appState.dispatch(.showCommandPalette)
                }
                .tooltip(KeyboardShortcuts.commandPalette)
                IconButton(systemName: "plus") {
                    appState.dispatch(.showProjectPicker)
                }
                .tooltip(KeyboardShortcuts.newProject)
            } else {
                IconButton(systemName: "plus") {
                    appState.dispatch(.showProjectPicker)
                }
                .tooltip(KeyboardShortcuts.newProject)
                IconButton(systemName: "command") {
                    appState.dispatch(.showCommandPalette)
                }
                .tooltip(KeyboardShortcuts.commandPalette)
                IconButton(systemName: "sidebar.left") { onToggleSidebar() }
                    .tooltip(KeyboardShortcuts.toggleSidebar)
            }
        }
        .frame(height: configStore.titlebarHeight)
    }

    @ViewBuilder
    private var projectList: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 2) {
                ReorderableStack(controller.workspace.projects, axis: .vertical, spacing: 2, hitTestHeight: 28) { project, isDragging in
                    SidebarProjectRow(
                        project: project,
                        isActive: project.id == controller.workspace.activeProjectId,
                        activeTabId: controller.workspace.activeTabId,
                        isExpanded: Binding(
                            get: { appState.expandedProjectIds.contains(project.id) },
                            set: {
                                if $0 { appState.expandedProjectIds.insert(project.id) } else { appState.expandedProjectIds.remove(project.id) }
                                let names = controller.workspace.projects
                                    .filter { appState.expandedProjectIds.contains($0.id) }
                                    .map(\.name)
                                controller.saveUIState(expandedProjectNames: names)
                            }
                        ),
                        onTabDraggedOut: { tab, edge in
                            let sessions = controller.workspace.projects
                            guard let srcIdx = sessions.firstIndex(where: { $0.id == project.id }) else { return }
                            let targetIdx = edge == .top ? srcIdx - 1 : srcIdx + 1
                            guard sessions.indices.contains(targetIdx) else { return }
                            controller.moveTab(tab, from: project, to: sessions[targetIdx])
                        },
                        projectIndex: controller.workspace.projects.firstIndex(where: { $0.id == project.id }).map { $0 + 1 } ?? 0
                    )
                    .contextMenu {
                        Button("Rename...") { appState.startProjectRename(project) }
                        Divider()
                        Button("New Tab") { controller.addTab(in: project) }
                        Divider()
                        Button("Close Project", role: .destructive) { controller.removeProject(project) }
                    }
                } onReorder: { from, to in
                    controller.workspace.projects.move(fromOffsets: IndexSet(integer: from), toOffset: to)
                }
            }
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture(count: 2) {
                    appState.dispatch(.showProjectPicker)
                }
        }
    }
}
