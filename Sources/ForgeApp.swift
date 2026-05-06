import SwiftUI
import ForgeCore

@main
struct ForgeApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings {
            SettingsView()
        }
        .commands {
            ForgeMenuCommands(controller: appDelegate.controller, config: appDelegate.configStore, appState: appDelegate.appState)
        }
    }
}

// MARK: - Notification Names

extension Notification.Name {
    static let forgeConfigChanged = Notification.Name("forgeConfigChanged")
    static let forgeWindowTitleChanged = Notification.Name("forgeWindowTitleChanged")
}

// MARK: - NSColor Helpers

extension NSColor {
    var isLight: Bool {
        guard let rgb = usingColorSpace(.sRGB) else { return false }
        let luminance = 0.299 * rgb.redComponent + 0.587 * rgb.greenComponent + 0.114 * rgb.blueComponent
        return luminance > 0.5
    }
}

// MARK: - App Delegate

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let configStore = ForgeConfigStore.shared
    lazy var controller = WorkspaceController(tmux: TmuxAdapter(), git: GitAdapter(), config: configStore)
    let appState = AppState(sidebarVisible: ForgeConfig.load().uiState?.sidebarVisible ?? true)
    private(set) var attentionManager: AttentionManager!
    private let debugServer = DebugServer()
    private var mainWindow: NSWindow?
    private var titleBarManager: TitleBarManager?
    private var appearanceObservation: NSKeyValueObservation?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)

        if let iconPath = Bundle.main.executableURL?.deletingLastPathComponent()
            .appendingPathComponent("AppIcon.icns"),
           let icon = NSImage(contentsOf: iconPath) {
            NSApp.applicationIconImage = icon
        }

        let notifier = MacNotificationAdapter()
        attentionManager = AttentionManager(notifier: notifier, config: configStore)
        controller.attentionManager = attentionManager

        createMainWindow()
        appState.bind(controller: controller, titleBarManager: titleBarManager, attentionManager: attentionManager, config: configStore)
        controller.connect()

        // Restore expanded project IDs after connect
        Task { @MainActor in
            // Give connect() a moment to populate workspace
            try? await Task.sleep(for: .milliseconds(500))
            if let names = ForgeConfig.load().uiState?.expandedProjectNames {
                let nameSet = Set(names)
                self.appState.expandedProjectIds = Set(self.controller.workspace.projects.filter { nameSet.contains($0.name) }.map(\.id))
            }
        }

        debugServer.start(controller: controller)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            self.cleanUpMenuBar()
        }

        // Appearance sync
        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeOcclusionStateNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.titleBarManager?.syncAppearance() }
        }
        appearanceObservation = NSApp.observe(\.effectiveAppearance, options: [.new]) { [weak self] _, _ in
            MainActor.assumeIsolated { self?.titleBarManager?.syncAppearance() }
        }
    }

    private func createMainWindow() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1200, height: 800),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.titlebarSeparatorStyle = .none
        window.minSize = NSSize(width: 800, height: 500)
        window.center()
        window.setFrameAutosaveName("ForgeMainWindow")

        let rootView = MainView()
            .environment(controller)
            .environment(attentionManager!)
            .environment(configStore)
            .environment(appState)
        window.contentView = NSHostingView(rootView: rootView)
        window.makeKeyAndOrderFront(nil)
        self.mainWindow = window

        let tbm = TitleBarManager(window: window, controller: controller, attentionManager: attentionManager, config: configStore, appState: appState)
        tbm.measureTitlebarHeight()
        tbm.syncAppearance()
        self.titleBarManager = tbm
    }

    private func cleanUpMenuBar() {
        guard let mainMenu = NSApp.mainMenu else { return }
        for menuItem in mainMenu.items {
            guard let submenu = menuItem.submenu else { continue }
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
        guard configStore.config.general?.confirmBeforeClose ?? true else {
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
