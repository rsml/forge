import SwiftUI

@main
struct ForgeApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @State private var tmux = TmuxController()

    var body: some Scene {
        Window("Forge", id: "main") {
            MainView()
                .environment(tmux)
                .frame(minWidth: 800, minHeight: 500)
                .onAppear {
                    tmux.connect()
                }
        }
        .windowStyle(.automatic)
        .defaultSize(width: 1200, height: 800)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate, @unchecked Sendable {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return true
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        let alert = NSAlert()
        alert.messageText = "Quit Forge?"
        alert.informativeText = "Your tmux sessions will keep running in the background."
        alert.addButton(withTitle: "Quit")
        alert.addButton(withTitle: "Cancel")
        alert.alertStyle = .warning

        if alert.runModal() == .alertFirstButtonReturn {
            return .terminateNow
        }
        return .terminateCancel
    }
}
