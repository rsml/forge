import Foundation
import AppKit
import ForgeCore

struct Command {
    let name: String
    let description: String
    let icon: String
    let execute: (String) -> Void
}

@Observable @MainActor
final class CommandRegistry {
    private(set) var commands: [Command] = []

    func register(_ command: Command) {
        commands.append(command)
    }

    func setup(controller: WorkspaceController, appState: AppState) {
        commands = []

        // Navigation
        register(Command(name: "go", description: "Jump to project or tab", icon: "arrow.right.circle") { arg in
            let term = arg.lowercased()
            for project in controller.workspace.projects {
                if project.name.lowercased().contains(term) {
                    controller.selectProject(project)
                    return
                }
                for tab in project.tabs {
                    if tab.name.lowercased().contains(term) {
                        controller.selectProject(project)
                        controller.selectTab(tab)
                        return
                    }
                }
            }
        })

        register(Command(name: "tab", description: "Jump to tab number", icon: "number") { arg in
            guard let n = Int(arg),
                  let project = controller.workspace.activeProject,
                  n > 0, n <= project.tabs.count else { return }
            controller.selectTab(project.tabs[n - 1])
        })

        // Project/Tab management
        register(Command(name: "new-project", description: "Open project picker", icon: "folder.badge.plus") { _ in
            appState.dispatch(.showProjectPicker)
        })

        register(Command(name: "new-tab", description: "Create tab in current project", icon: "plus.rectangle") { _ in
            if let project = controller.workspace.activeProject {
                controller.addTab(in: project)
            }
        })

        register(Command(name: "close-tab", description: "Close current tab", icon: "xmark.rectangle") { _ in
            if let project = controller.workspace.activeProject,
               let tabId = controller.workspace.activeTabId,
               let tab = project.tabs.first(where: { $0.id == tabId }) {
                controller.removeTab(tab, in: project)
            }
        })

        register(Command(name: "rename-tab", description: "Rename current tab", icon: "pencil") { arg in
            guard !arg.isEmpty,
                  let tabId = controller.workspace.activeTabId,
                  let project = controller.workspace.activeProject,
                  let tab = project.tabs.first(where: { $0.id == tabId }) else { return }
            controller.renameTab(tab, to: arg)
        })

        register(Command(name: "rename-project", description: "Rename current project", icon: "pencil.circle") { arg in
            guard !arg.isEmpty,
                  let project = controller.workspace.activeProject else { return }
            controller.renameProject(project, to: arg)
        })

        // Sidebar
        register(Command(name: "collapse-all", description: "Collapse all sidebar groups", icon: "rectangle.compress.vertical") { _ in
            appState.dispatch(.collapseAll)
        })

        register(Command(name: "expand-all", description: "Expand all sidebar groups", icon: "rectangle.expand.vertical") { _ in
            appState.dispatch(.expandAll)
        })

        // Appearance
        register(Command(name: "theme", description: "Open settings file", icon: "paintbrush") { _ in
            let configURL = ForgeConfig.configURL
            if !FileManager.default.fileExists(atPath: configURL.path) {
                ForgeConfig.defaultConfig.save()
            }
            NSWorkspace.shared.open(configURL)
        })

        register(Command(name: "toggle-sidebar", description: "Toggle sidebar visibility", icon: "sidebar.left") { _ in
            appState.dispatch(.toggleSidebar)
        })
    }
}
