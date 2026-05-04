import SwiftUI

@main
struct ForgeApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @State private var controller = WorkspaceController(tmux: TmuxAdapter())
    @State private var debugServer = DebugServer()

    var body: some Scene {
        SwiftUI.Window("", id: "main") {
            MainView()
                .environment(controller)
                .frame(minWidth: 800, minHeight: 500)
                .onAppear {
                    controller.connect()
                    debugServer.start(controller: controller)
                }
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1200, height: 800)
        .commands {
            ForgeMenuCommands(controller: controller)
        }

        Settings {
            SettingsView()
        }
    }
}

// MARK: - Menu Bar

struct ForgeMenuCommands: Commands {
    let controller: WorkspaceController

    var body: some Commands {
        // Remove Services menu
        CommandGroup(replacing: .systemServices) { }

        // MARK: File
        CommandGroup(replacing: .newItem) {
            Button("New Project...") {
                NotificationCenter.default.post(name: .forgeNewProject, object: nil)
            }
            .keyboardShortcut(KeyboardShortcuts.newProject.key, modifiers: KeyboardShortcuts.newProject.modifiers)

            Button("New Tab") {
                if let session = controller.workspace.activeSession {
                    controller.addWindow(in: session)
                }
            }
            .keyboardShortcut(KeyboardShortcuts.newTab.key, modifiers: KeyboardShortcuts.newTab.modifiers)

            Divider()

            Button("Close Pane") {
                controller.closeCurrentPane()
            }
            .keyboardShortcut(KeyboardShortcuts.closePane.key, modifiers: KeyboardShortcuts.closePane.modifiers)

            Button("Close Project") {
                guard let session = controller.workspace.activeSession else { return }
                let alert = NSAlert()
                alert.messageText = "Close project \"\(session.name)\"?"
                alert.informativeText = "This will close all tabs and remove the project from Forge."
                alert.addButton(withTitle: "Close Project")
                alert.addButton(withTitle: "Cancel")
                alert.alertStyle = .warning
                guard alert.runModal() == .alertFirstButtonReturn else { return }
                controller.removeSession(session)
            }
            .keyboardShortcut(KeyboardShortcuts.closeProject.key, modifiers: KeyboardShortcuts.closeProject.modifiers)

            Divider()

            Button("Rename Tab...") {
                NotificationCenter.default.post(name: .forgeRenameTab, object: nil)
            }
            .keyboardShortcut(KeyboardShortcuts.renameTab.key, modifiers: KeyboardShortcuts.renameTab.modifiers)

            Button("Rename Project...") {
                NotificationCenter.default.post(name: .forgeRenameProject, object: nil)
            }
            .keyboardShortcut(KeyboardShortcuts.renameProject.key, modifiers: KeyboardShortcuts.renameProject.modifiers)
        }

        // MARK: Edit — pass standard editing commands through to the active responder (terminal)
        CommandGroup(replacing: .pasteboard) {
            Button("Undo") { NSApp.sendAction(Selector(("undo:")), to: nil, from: nil) }
                .keyboardShortcut("z", modifiers: .command)
            Button("Redo") { NSApp.sendAction(Selector(("redo:")), to: nil, from: nil) }
                .keyboardShortcut("z", modifiers: [.command, .shift])
            Divider()
            Button("Cut") { NSApp.sendAction(#selector(NSText.cut(_:)), to: nil, from: nil) }
                .keyboardShortcut("x", modifiers: .command)
            Button("Copy") { NSApp.sendAction(#selector(NSText.copy(_:)), to: nil, from: nil) }
                .keyboardShortcut("c", modifiers: .command)
            Button("Paste") { NSApp.sendAction(#selector(NSText.paste(_:)), to: nil, from: nil) }
                .keyboardShortcut("v", modifiers: .command)
            Button("Select All") { NSApp.sendAction(#selector(NSText.selectAll(_:)), to: nil, from: nil) }
                .keyboardShortcut("a", modifiers: .command)
        }

        // MARK: View
        CommandMenu("View") {
            Button("Command Palette") {
                NotificationCenter.default.post(name: .forgeCommandPalette, object: nil)
            }
            .keyboardShortcut(KeyboardShortcuts.commandPalette.key, modifiers: KeyboardShortcuts.commandPalette.modifiers)

            Button("Toggle Sidebar") {
                NotificationCenter.default.post(name: .forgeToggleSidebar, object: nil)
            }
            .keyboardShortcut(KeyboardShortcuts.toggleSidebar.key, modifiers: KeyboardShortcuts.toggleSidebar.modifiers)

            Button("Notifications") {
                NotificationCenter.default.post(name: .forgeNotifications, object: nil)
            }
            .keyboardShortcut(KeyboardShortcuts.notifications.key, modifiers: KeyboardShortcuts.notifications.modifiers)

            Divider()

            Button("Split Horizontally") {
                controller.splitPane(direction: .horizontal)
            }
            .keyboardShortcut(KeyboardShortcuts.splitHorizontal.key, modifiers: KeyboardShortcuts.splitHorizontal.modifiers)

            Button("Split Vertically") {
                controller.splitPane(direction: .vertical)
            }
            .keyboardShortcut(KeyboardShortcuts.splitVertical.key, modifiers: KeyboardShortcuts.splitVertical.modifiers)

            Divider()

            Button("Clear Scrollback") {
                controller.clearScrollback()
            }
            .keyboardShortcut(KeyboardShortcuts.clearScrollback.key, modifiers: KeyboardShortcuts.clearScrollback.modifiers)
        }

        // MARK: Window — tab and project navigation
        CommandMenu("Window") {
            Menu("Switch to Tab") {
                ForEach(1...9, id: \.self) { n in
                    Button("Tab \(n)") {
                        guard let session = controller.workspace.activeSession,
                              session.windows.count >= n
                        else { return }
                        controller.selectWindow(session.windows[n - 1])
                    }
                    .keyboardShortcut(KeyEquivalent(Character("\(n)")), modifiers: .command)
                }
            }

            Menu("Switch to Project") {
                ForEach(Array(controller.workspace.sessions.enumerated().prefix(9)), id: \.element.id) { index, session in
                    Button(session.name) {
                        controller.selectSession(session)
                    }
                    .keyboardShortcut(KeyEquivalent(Character("\(index + 1)")), modifiers: .option)
                }
            }

            Divider()

            Button("Select Tab Left") {
                guard let session = controller.workspace.activeSession,
                      let windowId = controller.workspace.activeWindowId,
                      let idx = session.windows.firstIndex(where: { $0.id == windowId }),
                      idx > 0
                else { return }
                controller.selectWindow(session.windows[idx - 1])
            }
            .keyboardShortcut(KeyboardShortcuts.selectTabLeft.key, modifiers: KeyboardShortcuts.selectTabLeft.modifiers)

            Button("Select Tab Right") {
                guard let session = controller.workspace.activeSession,
                      let windowId = controller.workspace.activeWindowId,
                      let idx = session.windows.firstIndex(where: { $0.id == windowId }),
                      idx < session.windows.count - 1
                else { return }
                controller.selectWindow(session.windows[idx + 1])
            }
            .keyboardShortcut(KeyboardShortcuts.selectTabRight.key, modifiers: KeyboardShortcuts.selectTabRight.modifiers)

            Button("Move Tab Left") {
                NotificationCenter.default.post(name: .forgeMoveTabLeft, object: nil)
            }
            .keyboardShortcut(KeyboardShortcuts.moveTabLeft.key, modifiers: KeyboardShortcuts.moveTabLeft.modifiers)

            Button("Move Tab Right") {
                NotificationCenter.default.post(name: .forgeMoveTabRight, object: nil)
            }
            .keyboardShortcut(KeyboardShortcuts.moveTabRight.key, modifiers: KeyboardShortcuts.moveTabRight.modifiers)

            Divider()

            Button("Next Project") {
                let sessions = controller.workspace.sessions
                guard sessions.count > 1,
                      let activeId = controller.workspace.activeSessionId,
                      let idx = sessions.firstIndex(where: { $0.id == activeId })
                else { return }
                let next = sessions[(idx + 1) % sessions.count]
                controller.selectSession(next)
            }
            .keyboardShortcut(KeyboardShortcuts.nextProject.key, modifiers: KeyboardShortcuts.nextProject.modifiers)

            Button("Previous Project") {
                let sessions = controller.workspace.sessions
                guard sessions.count > 1,
                      let activeId = controller.workspace.activeSessionId,
                      let idx = sessions.firstIndex(where: { $0.id == activeId })
                else { return }
                let prev = sessions[(idx - 1 + sessions.count) % sessions.count]
                controller.selectSession(prev)
            }
            .keyboardShortcut(KeyboardShortcuts.prevProject.key, modifiers: KeyboardShortcuts.prevProject.modifiers)
        }

        // MARK: Help
        CommandMenu("Help") {
            Button("Forge Help") {
                NSApp.showHelp(nil)
            }
        }
    }

}

extension Notification.Name {
    static let forgeNewProject = Notification.Name("forgeNewProject")
    static let forgeCommandPalette = Notification.Name("forgeCommandPalette")
    static let forgeToggleSidebar = Notification.Name("forgeToggleSidebar")
    static let forgeMoveTabLeft = Notification.Name("forgeMoveTabLeft")
    static let forgeMoveTabRight = Notification.Name("forgeMoveTabRight")
    static let forgeNotifications = Notification.Name("forgeNotifications")
    static let forgeCollapseAll = Notification.Name("forgeCollapseAll")
    static let forgeExpandAll = Notification.Name("forgeExpandAll")
    static let forgeRenameTab = Notification.Name("forgeRenameTab")
    static let forgeRenameProject = Notification.Name("forgeRenameProject")
}

// MARK: - App Delegate

final class AppDelegate: NSObject, NSApplicationDelegate, @unchecked Sendable {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)

        // Remove unwanted default menu items after SwiftUI builds the menu bar
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            self.cleanUpMenuBar()
        }
    }

    private func cleanUpMenuBar() {
        guard let mainMenu = NSApp.mainMenu else { return }
        for menuItem in mainMenu.items {
            guard let submenu = menuItem.submenu else { continue }
            // Remove "Close" and "Close All" from File menu (SwiftUI defaults)
            if menuItem.title == "File" {
                submenu.items.removeAll { item in
                    item.title == "Close" || item.title == "Close All"
                }
            }
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard ForgeConfigStore.shared.config.general?.confirmBeforeClose ?? true else {
            return .terminateNow
        }
        let alert = NSAlert()
        alert.messageText = "Quit Forge?"
        alert.informativeText = "Your tmux sessions will keep running in the background."
        alert.addButton(withTitle: "Quit")
        alert.addButton(withTitle: "Cancel")
        alert.alertStyle = .warning
        return alert.runModal() == .alertFirstButtonReturn ? .terminateNow : .terminateCancel
    }
}
