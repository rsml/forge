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
            ForgeMenuCommands(controller: appDelegate.controller)
        }
    }
}

// MARK: - Notification Names

extension Notification.Name {
    static let forgeConfigChanged = Notification.Name("forgeConfigChanged")
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
    static let forgeToggleMode = Notification.Name("forgeToggleMode")
    static let forgeWindowTitleChanged = Notification.Name("forgeWindowTitleChanged")
    static let forgeStackDone = Notification.Name("forgeStackDone")
    static let forgeStackHide = Notification.Name("forgeStackHide")
    static let forgeStackMoveToBack = Notification.Name("forgeStackMoveToBack")
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
    let controller = WorkspaceController(tmux: TmuxAdapter(), git: GitAdapter())
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
        attentionManager = AttentionManager(notifier: notifier, config: ForgeConfigStore.shared)
        controller.attentionManager = attentionManager

        createMainWindow()
        controller.connect()
        debugServer.start(controller: controller)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            self.cleanUpMenuBar()
        }

        NotificationCenter.default.addObserver(
            forName: .forgeToggleMode, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                if ForgeConfigStore.shared.isStackMode {
                    if let uuid = self.attentionManager?.currentTabUUID,
                       let (project, tab) = self.controller.workspace.findTab(byUUID: uuid) {
                        self.controller.workspace.activeProjectId = project.id
                        self.controller.workspace.activeTabId = tab.id
                    }
                    ForgeConfigStore.shared.isStackMode = false
                } else {
                    if let tabId = self.controller.workspace.activeTabId,
                       let tab = self.controller.workspace.activeProject?.tabs.first(where: { $0.id == tabId }),
                       tab.needsAttention {
                        self.attentionManager?.promoteToFront(tab.uuid)
                    }
                    ForgeConfigStore.shared.isStackMode = true
                    if let uuid = self.attentionManager?.currentTabUUID,
                       let (_, tab) = self.controller.workspace.findTab(byUUID: uuid) {
                        self.controller.selectTab(tab)
                    }
                }
                self.titleBarManager?.updateSplitIconVisibility()
                self.titleBarManager?.updateWindowTitle()
                DispatchQueue.main.async {
                    self.titleBarManager?.updateOverlayConstraints()
                }
            }
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
        window.contentView = NSHostingView(rootView: rootView)
        window.makeKeyAndOrderFront(nil)
        self.mainWindow = window

        let tbm = TitleBarManager(window: window, controller: controller, attentionManager: attentionManager)
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
