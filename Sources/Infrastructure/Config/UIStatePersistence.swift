import Foundation
import ForgeCore

@MainActor
final class UIStatePersistence {
    private let config: ForgeConfigStore

    init(config: ForgeConfigStore) {
        self.config = config
    }

    func save(workspace: Workspace, sidebarVisible: Bool? = nil, expandedProjectNames: [String]? = nil) {
        let activeProject = workspace.projects.first { $0.id == workspace.activeProjectId }
        let activeTab = activeProject?.tabs.first { $0.id == workspace.activeTabId }

        config.update { config in
            var state = config.uiState ?? ForgeConfig.UIState()
            state.activeProjectName = activeProject?.name
            state.activeTabIndex = activeTab?.index
            if let sidebarVisible { state.sidebarVisible = sidebarVisible }
            if let expandedProjectNames { state.expandedProjectNames = expandedProjectNames }
            config.uiState = state
        }
    }

    func restore(workspace: Workspace, tmux: any TmuxPort) {
        guard let state = ForgeConfig.load().uiState else { return }

        if let name = state.activeProjectName,
           let project = workspace.projects.first(where: { $0.name == name }) {
            workspace.activeProjectId = project.id
            Task { await tmux.switchClient(project: project.name) }

            if let index = state.activeTabIndex,
               let tab = project.tabs.first(where: { $0.index == index }) {
                workspace.activeTabId = tab.id
                Task { await tmux.selectTab(id: tab.id) }
            } else if let first = project.tabs.first {
                workspace.activeTabId = first.id
            }
        }
    }

    func seedRecentDirectories(from workspace: Workspace) {
        let paths = workspace.projects.compactMap { project -> String? in
            guard let path = project.path, !path.isEmpty, path != NSHomeDirectory() else { return nil }
            return path
        }
        guard !paths.isEmpty else { return }
        config.update { config in
            for path in paths where !config.recentDirectories.contains(path) {
                config.recentDirectories.append(path)
            }
            if config.recentDirectories.count > 20 {
                config.recentDirectories = Array(config.recentDirectories.prefix(20))
            }
        }
    }
}
