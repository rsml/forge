import Foundation
import AppKit
import ForgeCore

struct Command {
    let name: String
    let description: String
    let icon: String
    let shortcutHint: String?
    let execute: (String) -> Void

    init(name: String, description: String, icon: String, shortcutHint: String? = nil, execute: @escaping (String) -> Void) {
        self.name = name
        self.description = description
        self.icon = icon
        self.shortcutHint = shortcutHint
        self.execute = execute
    }
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
        register(Command(name: "new-project", description: "Open project picker", icon: "folder.badge.plus", shortcutHint: KeyboardShortcuts.newProject.hint) { _ in
            appState.dispatch(.showProjectPicker)
        })

        register(Command(name: "new-tab", description: "Create tab in current project", icon: "plus.rectangle", shortcutHint: KeyboardShortcuts.newTab.hint) { _ in
            if let project = controller.workspace.activeProject {
                controller.addTab(in: project)
            }
        })

        register(Command(name: "close-pane", description: "Close current pane", icon: "xmark.rectangle", shortcutHint: KeyboardShortcuts.closePane.hint) { _ in
            controller.closeCurrentPane()
        })

        register(Command(name: "close-project", description: "Close current project", icon: "xmark.circle", shortcutHint: KeyboardShortcuts.closeProject.hint) { _ in
            guard let project = controller.workspace.activeProject else { return }
            let alert = NSAlert()
            alert.messageText = "Close project \"\(project.name)\"?"
            alert.informativeText = "This will close all tabs and remove the project from Forge."
            alert.addButton(withTitle: "Close Project")
            alert.addButton(withTitle: "Cancel")
            alert.alertStyle = .warning
            guard alert.runModal() == .alertFirstButtonReturn else { return }
            controller.removeProject(project)
        })

        register(Command(name: "rename-tab", description: "Rename current tab", icon: "pencil", shortcutHint: KeyboardShortcuts.renameTab.hint) { arg in
            if arg.isEmpty {
                appState.dispatch(.renameTab)
            } else {
                guard let tabId = controller.workspace.activeTabId,
                      let project = controller.workspace.activeProject,
                      let tab = project.tabs.first(where: { $0.id == tabId }) else { return }
                controller.renameTab(tab, to: arg)
            }
        })

        register(Command(name: "rename-project", description: "Rename current project", icon: "pencil.circle", shortcutHint: KeyboardShortcuts.renameProject.hint) { arg in
            if arg.isEmpty {
                appState.dispatch(.renameProject)
            } else {
                guard let project = controller.workspace.activeProject else { return }
                controller.renameProject(project, to: arg)
            }
        })

        // Sidebar
        register(Command(name: "collapse-all", description: "Collapse all sidebar groups", icon: "rectangle.compress.vertical") { _ in
            appState.dispatch(.collapseAll)
        })

        register(Command(name: "expand-all", description: "Expand all sidebar groups", icon: "rectangle.expand.vertical") { _ in
            appState.dispatch(.expandAll)
        })

        // View
        register(Command(name: "toggle-sidebar", description: "Toggle sidebar visibility", icon: "sidebar.left", shortcutHint: KeyboardShortcuts.toggleSidebar.hint) { _ in
            appState.dispatch(.toggleSidebar)
        })

        register(Command(name: "notifications", description: "Show notifications", icon: "bell", shortcutHint: KeyboardShortcuts.notifications.hint) { _ in
            appState.dispatch(.showNotifications)
        })

        register(Command(name: "toggle-mode", description: "Toggle list/stack mode", icon: "rectangle.stack", shortcutHint: KeyboardShortcuts.toggleMode.hint) { _ in
            appState.dispatch(.toggleMode)
        })

        // Splits
        register(Command(name: "split-horizontal", description: "Split pane horizontally", icon: "square.split.2x1", shortcutHint: KeyboardShortcuts.splitHorizontal.hint) { _ in
            controller.splitPane(direction: .horizontal)
        })

        register(Command(name: "split-vertical", description: "Split pane vertically", icon: "square.split.1x2", shortcutHint: KeyboardShortcuts.splitVertical.hint) { _ in
            controller.splitPane(direction: .vertical)
        })

        // Tab navigation
        register(Command(name: "select-tab-left", description: "Select tab to the left", icon: "chevron.left", shortcutHint: KeyboardShortcuts.selectTabLeft.hint) { _ in
            guard let project = controller.workspace.activeProject,
                  let tabId = controller.workspace.activeTabId,
                  let idx = project.tabs.firstIndex(where: { $0.id == tabId }),
                  idx > 0 else { return }
            controller.selectTab(project.tabs[idx - 1])
        })

        register(Command(name: "select-tab-right", description: "Select tab to the right", icon: "chevron.right", shortcutHint: KeyboardShortcuts.selectTabRight.hint) { _ in
            guard let project = controller.workspace.activeProject,
                  let tabId = controller.workspace.activeTabId,
                  let idx = project.tabs.firstIndex(where: { $0.id == tabId }),
                  idx < project.tabs.count - 1 else { return }
            controller.selectTab(project.tabs[idx + 1])
        })

        register(Command(name: "move-tab-left", description: "Move tab left", icon: "arrow.left.to.line", shortcutHint: KeyboardShortcuts.moveTabLeft.hint) { _ in
            appState.dispatch(.moveTabLeft)
        })

        register(Command(name: "move-tab-right", description: "Move tab right", icon: "arrow.right.to.line", shortcutHint: KeyboardShortcuts.moveTabRight.hint) { _ in
            appState.dispatch(.moveTabRight)
        })

        // Project navigation
        register(Command(name: "next-project", description: "Switch to next project", icon: "chevron.down", shortcutHint: KeyboardShortcuts.nextProject.hint) { _ in
            let projects = controller.workspace.projects
            guard projects.count > 1,
                  let activeId = controller.workspace.activeProjectId,
                  let idx = projects.firstIndex(where: { $0.id == activeId }) else { return }
            controller.selectProject(projects[(idx + 1) % projects.count])
        })

        register(Command(name: "prev-project", description: "Switch to previous project", icon: "chevron.up", shortcutHint: KeyboardShortcuts.prevProject.hint) { _ in
            let projects = controller.workspace.projects
            guard projects.count > 1,
                  let activeId = controller.workspace.activeProjectId,
                  let idx = projects.firstIndex(where: { $0.id == activeId }) else { return }
            controller.selectProject(projects[(idx - 1 + projects.count) % projects.count])
        })

        // Appearance
        register(Command(name: "theme", description: "Open settings file", icon: "paintbrush") { _ in
            let configURL = ForgeConfig.configURL
            if !FileManager.default.fileExists(atPath: configURL.path) {
                ForgeConfig.defaultConfig.save()
            }
            NSWorkspace.shared.open(configURL)
        })

        // App
        register(Command(name: "settings", description: "Open settings", icon: "gearshape", shortcutHint: KeyboardShortcuts.settings.hint) { _ in
            NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
        })

        register(Command(name: "clear-scrollback", description: "Clear terminal scrollback", icon: "eraser", shortcutHint: KeyboardShortcuts.clearScrollback.hint) { _ in
            controller.clearScrollback()
        })
    }
}
