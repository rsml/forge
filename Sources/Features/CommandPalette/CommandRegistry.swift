import Foundation
import AppKit
import ForgeCore

struct Command {
    let label: String
    let shortcutHint: String?
    let action: () -> Void

    init(label: String, shortcutHint: String? = nil, action: @escaping () -> Void) {
        self.label = label
        self.shortcutHint = shortcutHint
        self.action = action
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

        // File
        register(Command(label: KeyboardShortcuts.newProject.label, shortcutHint: KeyboardShortcuts.newProject.hint) {
            appState.dispatch(.showProjectPicker)
        })
        register(Command(label: KeyboardShortcuts.newTab.label, shortcutHint: KeyboardShortcuts.newTab.hint) {
            if let project = controller.workspace.activeProject {
                controller.addTab(in: project)
            }
        })
        register(Command(label: KeyboardShortcuts.closePane.label, shortcutHint: KeyboardShortcuts.closePane.hint) {
            controller.closeCurrentPane()
        })
        register(Command(label: KeyboardShortcuts.closeProject.label, shortcutHint: KeyboardShortcuts.closeProject.hint) {
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
        register(Command(label: KeyboardShortcuts.renameTab.label, shortcutHint: KeyboardShortcuts.renameTab.hint) {
            appState.dispatch(.renameTab)
        })
        register(Command(label: KeyboardShortcuts.renameProject.label, shortcutHint: KeyboardShortcuts.renameProject.hint) {
            appState.dispatch(.renameProject)
        })

        // View
        register(Command(label: KeyboardShortcuts.toggleSidebar.label, shortcutHint: KeyboardShortcuts.toggleSidebar.hint) {
            appState.dispatch(.toggleSidebar)
        })
        register(Command(label: KeyboardShortcuts.notifications.label, shortcutHint: KeyboardShortcuts.notifications.hint) {
            appState.dispatch(.showNotifications)
        })
        register(Command(label: KeyboardShortcuts.toggleMode.label, shortcutHint: KeyboardShortcuts.toggleMode.hint) {
            appState.dispatch(.toggleMode)
        })

        // Splits
        register(Command(label: KeyboardShortcuts.splitHorizontal.label, shortcutHint: KeyboardShortcuts.splitHorizontal.hint) {
            controller.splitPane(direction: .horizontal)
        })
        register(Command(label: KeyboardShortcuts.splitVertical.label, shortcutHint: KeyboardShortcuts.splitVertical.hint) {
            controller.splitPane(direction: .vertical)
        })

        // Tab navigation
        register(Command(label: KeyboardShortcuts.selectTabLeft.label, shortcutHint: KeyboardShortcuts.selectTabLeft.hint) {
            guard let project = controller.workspace.activeProject,
                  let tabId = controller.workspace.activeTabId,
                  let idx = project.tabs.firstIndex(where: { $0.id == tabId }),
                  idx > 0 else { return }
            controller.selectTab(project.tabs[idx - 1])
        })
        register(Command(label: KeyboardShortcuts.selectTabRight.label, shortcutHint: KeyboardShortcuts.selectTabRight.hint) {
            guard let project = controller.workspace.activeProject,
                  let tabId = controller.workspace.activeTabId,
                  let idx = project.tabs.firstIndex(where: { $0.id == tabId }),
                  idx < project.tabs.count - 1 else { return }
            controller.selectTab(project.tabs[idx + 1])
        })
        register(Command(label: KeyboardShortcuts.moveTabLeft.label, shortcutHint: KeyboardShortcuts.moveTabLeft.hint) {
            appState.dispatch(.moveTabLeft)
        })
        register(Command(label: KeyboardShortcuts.moveTabRight.label, shortcutHint: KeyboardShortcuts.moveTabRight.hint) {
            appState.dispatch(.moveTabRight)
        })

        // Project navigation
        register(Command(label: KeyboardShortcuts.nextProject.label, shortcutHint: KeyboardShortcuts.nextProject.hint) {
            let projects = controller.workspace.projects
            guard projects.count > 1,
                  let activeId = controller.workspace.activeProjectId,
                  let idx = projects.firstIndex(where: { $0.id == activeId }) else { return }
            controller.selectProject(projects[(idx + 1) % projects.count])
        })
        register(Command(label: KeyboardShortcuts.prevProject.label, shortcutHint: KeyboardShortcuts.prevProject.hint) {
            let projects = controller.workspace.projects
            guard projects.count > 1,
                  let activeId = controller.workspace.activeProjectId,
                  let idx = projects.firstIndex(where: { $0.id == activeId }) else { return }
            controller.selectProject(projects[(idx - 1 + projects.count) % projects.count])
        })

        // Sidebar
        register(Command(label: "Collapse All") {
            appState.dispatch(.collapseAll)
        })
        register(Command(label: "Expand All") {
            appState.dispatch(.expandAll)
        })

        // App
        register(Command(label: KeyboardShortcuts.settings.label, shortcutHint: KeyboardShortcuts.settings.hint) {
            NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
        })
        register(Command(label: KeyboardShortcuts.clearScrollback.label, shortcutHint: KeyboardShortcuts.clearScrollback.hint) {
            controller.clearScrollback()
        })
        register(Command(label: "Open Config File") {
            let configURL = ForgeConfig.configURL
            if !FileManager.default.fileExists(atPath: configURL.path) {
                ForgeConfig.defaultConfig.save()
            }
            NSWorkspace.shared.open(configURL)
        })
    }
}
