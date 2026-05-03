import SwiftUI

@main
struct ForgeApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @State private var controller = WorkspaceController(tmux: TmuxAdapter())
    @State private var debugServer = DebugServer()

    var body: some Scene {
        SwiftUI.Window("Forge", id: "main") {
            MainView()
                .environment(controller)
                .frame(minWidth: 800, minHeight: 500)
                .onAppear {
                    controller.connect()
                    debugServer.start(controller: controller)
                }
        }
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified(showsTitle: false))
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
            .keyboardShortcut("o")

            Button("New Tab") {
                if let session = controller.workspace.activeSession {
                    controller.addWindow(in: session)
                }
            }
            .keyboardShortcut("t")

            Divider()

            Button("Close Tab") {
                if let session = controller.workspace.activeSession,
                   let windowId = controller.workspace.activeWindowId,
                   let window = session.windows.first(where: { $0.id == windowId }) {
                    controller.removeWindow(window)
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
}

// MARK: - App Delegate

final class AppDelegate: NSObject, NSApplicationDelegate, @unchecked Sendable {
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
