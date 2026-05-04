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
        .windowStyle(.automatic)
        .defaultSize(width: 1200, height: 800)
        .commands {
            ForgeMenuCommands(controller: controller)
        }
    }
}

// MARK: - Menu Bar

struct ForgeMenuCommands: Commands {
    let controller: WorkspaceController

    var body: some Commands {
        // Replace "New Window" in File menu
        CommandGroup(replacing: .newItem) {
            Button("New Project...") {
                NotificationCenter.default.post(name: .forgeNewProject, object: nil)
            }
            .keyboardShortcut("n")

            Button("New Tab") {
                if let session = controller.workspace.activeSession {
                    controller.addWindow(in: session)
                }
            }
            .keyboardShortcut("t")

            Divider()

            Button("Close Tab") {
                guard let session = controller.workspace.activeSession,
                      let windowId = controller.workspace.activeWindowId,
                      let window = session.windows.first(where: { $0.id == windowId })
                else { return }
                if session.windows.count <= 1 {
                    let alert = NSAlert()
                    alert.messageText = "Close project \"\(session.name)\"?"
                    alert.informativeText = "This will close the last tab and remove the project from Forge."
                    alert.addButton(withTitle: "Close Project")
                    alert.addButton(withTitle: "Cancel")
                    alert.alertStyle = .warning
                    guard alert.runModal() == .alertFirstButtonReturn else { return }
                    controller.removeSession(session)
                } else {
                    controller.removeWindow(window, in: session)
                }
            }
            .keyboardShortcut("w")
        }

        CommandGroup(after: .appSettings) {
            Button("Settings...") {
                openSettings()
            }
            .keyboardShortcut(",")
        }

        CommandMenu("View") {
            Button("Toggle Sidebar") {
                NotificationCenter.default.post(name: .forgeToggleSidebar, object: nil)
            }
            .keyboardShortcut("b")

            Button("Command Palette") {
                NotificationCenter.default.post(name: .forgeCommandPalette, object: nil)
            }
            .keyboardShortcut("p")

            Divider()

            Button("Select Tab Left") {
                guard let session = controller.workspace.activeSession,
                      let windowId = controller.workspace.activeWindowId,
                      let idx = session.windows.firstIndex(where: { $0.id == windowId }),
                      idx > 0
                else { return }
                controller.selectWindow(session.windows[idx - 1])
            }
            .keyboardShortcut("[", modifiers: [.command, .shift])

            Button("Select Tab Right") {
                guard let session = controller.workspace.activeSession,
                      let windowId = controller.workspace.activeWindowId,
                      let idx = session.windows.firstIndex(where: { $0.id == windowId }),
                      idx < session.windows.count - 1
                else { return }
                controller.selectWindow(session.windows[idx + 1])
            }
            .keyboardShortcut("]", modifiers: [.command, .shift])

            Button("Move Tab Left") {
                NotificationCenter.default.post(name: .forgeMoveTabLeft, object: nil)
            }
            .keyboardShortcut(.leftArrow, modifiers: [.command, .shift])

            Button("Move Tab Right") {
                NotificationCenter.default.post(name: .forgeMoveTabRight, object: nil)
            }
            .keyboardShortcut(.rightArrow, modifiers: [.command, .shift])

            Divider()

            ForEach(1...9, id: \.self) { n in
                Button("Tab \(n)") {
                    guard let session = controller.workspace.activeSession,
                          session.windows.count >= n
                    else { return }
                    controller.selectWindow(session.windows[n - 1])
                }
                .keyboardShortcut(KeyEquivalent(Character("\(n)")), modifiers: .command)
            }

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
            .keyboardShortcut(KeyEquivalent("\t"), modifiers: .control)

            Button("Previous Project") {
                let sessions = controller.workspace.sessions
                guard sessions.count > 1,
                      let activeId = controller.workspace.activeSessionId,
                      let idx = sessions.firstIndex(where: { $0.id == activeId })
                else { return }
                let prev = sessions[(idx - 1 + sessions.count) % sessions.count]
                controller.selectSession(prev)
            }
            .keyboardShortcut(KeyEquivalent("\t"), modifiers: [.control, .shift])
        }
    }

    private func openSettings() {
        let configURL = ForgeConfig.configURL
        // Ensure file exists
        if !FileManager.default.fileExists(atPath: configURL.path) {
            ForgeConfig.defaultConfig.save()
        }
        NSWorkspace.shared.open(configURL)
    }
}

extension Notification.Name {
    static let forgeNewProject = Notification.Name("forgeNewProject")
    static let forgeCommandPalette = Notification.Name("forgeCommandPalette")
    static let forgeToggleSidebar = Notification.Name("forgeToggleSidebar")
    static let forgeMoveTabLeft = Notification.Name("forgeMoveTabLeft")
    static let forgeMoveTabRight = Notification.Name("forgeMoveTabRight")
    static let forgeCollapseAll = Notification.Name("forgeCollapseAll")
    static let forgeExpandAll = Notification.Name("forgeExpandAll")
}

// MARK: - App Delegate

final class AppDelegate: NSObject, NSApplicationDelegate, @unchecked Sendable {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        let alert = NSAlert()
        alert.messageText = "Quit Forge?"
        alert.informativeText = "Your tmux sessions will keep running in the background."
        alert.addButton(withTitle: "Quit")
        alert.addButton(withTitle: "Cancel")
        alert.alertStyle = .warning
        return alert.runModal() == .alertFirstButtonReturn ? .terminateNow : .terminateCancel
    }
}
