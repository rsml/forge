import SwiftUI
import ForgeCore

@main
struct ForgeApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings {
            SettingsView()
                .environment(appDelegate.configStore)
                .environment(appDelegate.toastState)
        }
        .commands {
            ForgeMenuCommands(controller: appDelegate.controller, config: appDelegate.configStore, appState: appDelegate.appState)
        }
    }
}

// MARK: - Bundle Resource Lookup

/// Finds a resource file, checking Contents/Resources/ first (.app bundle), then next to the executable (bare SPM build).
func bundleResource(_ filename: String) -> URL? {
    if let url = Bundle.main.resourceURL?.appendingPathComponent(filename),
       FileManager.default.fileExists(atPath: url.path) {
        return url
    }
    if let url = Bundle.main.executableURL?.deletingLastPathComponent().appendingPathComponent(filename),
       FileManager.default.fileExists(atPath: url.path) {
        return url
    }
    return nil
}

// MARK: - Notification Names

extension Notification.Name {
    static let forgeConfigChanged = Notification.Name("forgeConfigChanged")
    static let forgeNavigateToTab = Notification.Name("forgeNavigateToTab")
    static let forgeFocusTerminal = Notification.Name("forgeFocusTerminal")
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
    let toastState = NotificationToastState()
    lazy var controller = WorkspaceController(tmux: TmuxAdapter(), config: configStore, toastState: toastState)
    let appState = AppState(sidebarVisible: ForgeConfig.load().uiState?.sidebarVisible ?? true)
    let commandRegistry = CommandRegistry()
    let modifierKeyMonitor = ModifierKeyMonitor()
    private(set) var attentionManager: AttentionManager!
    private(set) var ghosttyApp: GhosttyApp?
    private let debugServer = DebugServer()
    private var mainWindow: NSWindow?
    private var titleBarManager: TitleBarManager?
    private var appearanceObservation: NSKeyValueObservation?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)

        if let iconPath = bundleResource("AppIcon.icns"),
           let icon = NSImage(contentsOf: iconPath) {
            NSApp.applicationIconImage = icon
        }

        KeyboardShortcuts.config = configStore
        let notifier = MacNotificationAdapter(toastState: toastState)
        attentionManager = AttentionManager(notifier: notifier, config: configStore)
        controller.attentionManager = attentionManager
        controller.notifier = notifier

        if configStore.isNativePaneRendering || configStore.isNativePTY {
            let ga = GhosttyApp()
            ghosttyApp = ga
            applyGhosttyTheme()
        }
        controller.ghosttyApp = ghosttyApp
        if configStore.isNativePTY, let ga = ghosttyApp {
            controller.processAdapter = ProcessAdapter(ghosttyApp: ga)
            let daemon = DaemonAdapter()
            controller.daemonAdapter = daemon
            controller.activityPort = DaemonActivityAdapter(daemon: daemon)
            // Launch and connect to daemon immediately
            Task {
                do {
                    try daemon.ensureConnected()
                    ForgeLog.log("[app] Connected to forged daemon")
                } catch {
                    ForgeLog.log("[app] Failed to connect to daemon: \(error)")
                }
            }
        } else {
            controller.activityPort = TmuxActivityAdapter(workspace: controller.workspace)
        }

        createMainWindow()
        appState.bind(
            controller: controller,
            attentionManager: attentionManager,
            config: configStore,
            onModeChanged: { [weak self] in
                self?.titleBarManager?.updateSplitIconVisibility()
                self?.titleBarManager?.updateWindowTitle()
                DispatchQueue.main.async {
                    self?.titleBarManager?.updateOverlayConstraints()
                }
            }
        )
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
        NotificationCenter.default.addObserver(
            forName: .forgeConfigChanged, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.applyGhosttyTheme() }
        }
    }

    private func applyGhosttyTheme(overrideTheme: ThemeDefinition? = nil) {
        guard let ga = ghosttyApp else { return }
        let fontFamily = configStore.config.terminalFont?.family
            ?? configStore.config.terminal?.fontFamily
            ?? configStore.config.appearance?.fontFamily
        let fontSize = configStore.config.terminalFont?.size
            ?? configStore.config.terminal?.fontSize
            ?? configStore.config.appearance?.fontSize ?? 13
        let theme = overrideTheme ?? configStore.resolvedTheme
        var fgHex: String?
        var bgHex: String?
        var ansiHex: [String]?
        if let theme {
            fgHex = String(format: "#%02x%02x%02x",
                Int(theme.foreground.red * 255),
                Int(theme.foreground.green * 255),
                Int(theme.foreground.blue * 255))
            bgHex = String(format: "#%02x%02x%02x",
                Int(theme.background.red * 255),
                Int(theme.background.green * 255),
                Int(theme.background.blue * 255))
            ansiHex = theme.ansiColors.prefix(16).map { c in
                String(format: "#%02x%02x%02x", Int(c.red * 255), Int(c.green * 255), Int(c.blue * 255))
            }
        }
        ga.applyConfig(fontFamily: fontFamily, fontSize: fontSize,
                       foreground: fgHex, background: bgHex, ansiColors: ansiHex)
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
            .environment(commandRegistry)
            .environment(modifierKeyMonitor)
            .environment(toastState)
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
        // In native PTY mode, save workspace before quitting.
        // Daemon keeps fds alive; workspace.json preserves structure.
        if configStore.isNativePTY {
            let windowFrame = NSApp.mainWindow?.frame
            WorkspacePersistence.save(workspace: controller.workspace, windowFrame: windowFrame)
            ForgeLog.log("[app] Saved workspace for native PTY persistence")
            // _exit() bypasses AppKit teardown which would destroy Ghostty surfaces
            // and send SIGHUP to child processes. The daemon holds fd dups, so
            // PTYs stay alive. Child processes keep running.
            _exit(0)
        }

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
