import Foundation
import AppKit
import ForgeDomain

struct Command {
    let name: String
    let description: String
    let icon: String
    let execute: (String) -> Void
}

@MainActor
final class CommandRegistry {
    static let shared = CommandRegistry()
    private(set) var commands: [Command] = []

    private init() {}

    func register(_ command: Command) {
        commands.append(command)
    }

    func setup(controller: WorkspaceController) {
        commands = []

        // Navigation
        register(Command(name: "go", description: "Jump to session or tab", icon: "arrow.right.circle") { arg in
            let term = arg.lowercased()
            for session in controller.workspace.sessions {
                if session.name.lowercased().contains(term) {
                    controller.selectSession(session)
                    return
                }
                for window in session.windows {
                    if window.name.lowercased().contains(term) {
                        controller.selectSession(session)
                        controller.selectWindow(window)
                        return
                    }
                }
            }
        })

        register(Command(name: "tab", description: "Jump to tab number", icon: "number") { arg in
            guard let n = Int(arg),
                  let session = controller.workspace.activeSession,
                  n > 0, n <= session.windows.count else { return }
            controller.selectWindow(session.windows[n - 1])
        })

        // Session/Tab management
        register(Command(name: "new-project", description: "Open project picker", icon: "folder.badge.plus") { _ in
            NotificationCenter.default.post(name: .forgeNewProject, object: nil)
        })

        register(Command(name: "new-tab", description: "Create tab in current session", icon: "plus.rectangle") { _ in
            if let session = controller.workspace.activeSession {
                controller.addWindow(in: session)
            }
        })

        register(Command(name: "close-tab", description: "Close current tab", icon: "xmark.rectangle") { _ in
            if let session = controller.workspace.activeSession,
               let windowId = controller.workspace.activeWindowId,
               let window = session.windows.first(where: { $0.id == windowId }) {
                controller.removeWindow(window, in: session)
            }
        })

        register(Command(name: "rename-tab", description: "Rename current tab", icon: "pencil") { arg in
            guard !arg.isEmpty,
                  let windowId = controller.workspace.activeWindowId,
                  let session = controller.workspace.activeSession,
                  let window = session.windows.first(where: { $0.id == windowId }) else { return }
            controller.renameWindow(window, to: arg)
        })

        register(Command(name: "rename-project", description: "Rename current session", icon: "pencil.circle") { arg in
            guard !arg.isEmpty,
                  let session = controller.workspace.activeSession else { return }
            controller.renameSession(session, to: arg)
        })

        // Sidebar
        register(Command(name: "collapse-all", description: "Collapse all sidebar groups", icon: "rectangle.compress.vertical") { _ in
            NotificationCenter.default.post(name: .forgeCollapseAll, object: nil)
        })

        register(Command(name: "expand-all", description: "Expand all sidebar groups", icon: "rectangle.expand.vertical") { _ in
            NotificationCenter.default.post(name: .forgeExpandAll, object: nil)
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
            NotificationCenter.default.post(name: .forgeToggleSidebar, object: nil)
        })
    }
}
