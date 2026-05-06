import SwiftUI
import ForgeCore

struct SidebarProjectList: View {
    var position: String = "left"
    var onToggleSidebar: () -> Void = {}
    @Environment(WorkspaceController.self) var controller
    @State private var expandedProjects: Set<String> = []
    @State private var renamingProjectId: String?
    @State private var renamingTabId: String?
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
            if let names = ForgeConfig.load().uiState?.expandedProjectNames {
                let nameSet = Set(names)
                expandedProjects = Set(controller.workspace.projects
                    .filter { nameSet.contains($0.name) }
                    .map(\.id))
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .forgeRenameProject)) { _ in
            guard let project = controller.workspace.activeProject else { return }
            renamingTabId = nil
            renameText = project.name
            renamingProjectId = project.id
        }
    }

    @ViewBuilder
    private var toolbarRow: some View {
        HStack(spacing: 0) {
            if position == "right" {
                IconButton(systemName: "sidebar.right") { onToggleSidebar() }
                    .tooltip(KeyboardShortcuts.toggleSidebar)
                IconButton(systemName: "command") {
                    NotificationCenter.default.post(name: .forgeCommandPalette, object: nil)
                }
                .tooltip(KeyboardShortcuts.commandPalette)
                IconButton(systemName: "plus") {
                    NotificationCenter.default.post(name: .forgeNewProject, object: nil)
                }
                .tooltip(KeyboardShortcuts.newProject)
            } else {
                IconButton(systemName: "plus") {
                    NotificationCenter.default.post(name: .forgeNewProject, object: nil)
                }
                .tooltip(KeyboardShortcuts.newProject)
                IconButton(systemName: "command") {
                    NotificationCenter.default.post(name: .forgeCommandPalette, object: nil)
                }
                .tooltip(KeyboardShortcuts.commandPalette)
                IconButton(systemName: "sidebar.left") { onToggleSidebar() }
                    .tooltip(KeyboardShortcuts.toggleSidebar)
            }
        }
        .frame(height: ForgeConfigStore.shared.titlebarHeight)
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
                            get: { expandedProjects.contains(project.id) },
                            set: {
                                if $0 { expandedProjects.insert(project.id) } else { expandedProjects.remove(project.id) }
                                let names = controller.workspace.projects
                                    .filter { expandedProjects.contains($0.id) }
                                    .map(\.name)
                                controller.saveUIState(expandedProjectNames: names)
                            }
                        ),
                        isRenaming: renamingProjectId == project.id,
                        renameText: $renameText,
                        onRenameCommit: {
                            if !renameText.isEmpty {
                                project.name = renameText // Optimistic update
                                controller.renameProject(project, to: renameText)
                            }
                            renamingProjectId = nil
                        },
                        onRenameCancel: { renamingProjectId = nil },
                        renamingTabId: renamingTabId,
                        onStartTabRename: { tab in
                            renamingProjectId = nil
                            renamingTabId = tab.id
                            renameText = tab.name
                        },
                        onRenameTabCommit: {
                            if !renameText.isEmpty,
                               let tab = project.tabs.first(where: { $0.id == renamingTabId }) {
                                tab.name = renameText // Optimistic update
                                controller.renameTab(tab, to: renameText)
                            }
                            renamingTabId = nil
                        },
                        onRenameTabCancel: { renamingTabId = nil },
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
                        Button("Rename...") {
                            renamingTabId = nil
                            renameText = project.name
                            renamingProjectId = project.id
                        }
                        Divider()
                        Button("New Tab") { controller.addTab(in: project) }
                        Divider()
                        Button("Close Project", role: .destructive) { controller.removeProject(project) }
                    }
                } onReorder: { from, to in
                    controller.workspace.projects.move(fromOffsets: IndexSet(integer: from), toOffset: to)
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
