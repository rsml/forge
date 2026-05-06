import SwiftUI
import ForgeDomain

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

// MARK: - Menu Bar

struct ForgeMenuCommands: Commands {
    let controller: WorkspaceController

    var body: some Commands {
        CommandGroup(replacing: .appInfo) {
            Button("About Forge") {
                let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.1"
                let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
                let alert = NSAlert()
                alert.messageText = "Forge \(version) (\(build))"
                alert.informativeText = "A native macOS frontend for tmux."
                alert.alertStyle = .informational
                if let iconPath = Bundle.main.executableURL?.deletingLastPathComponent()
                    .appendingPathComponent("appicon-transparent.png"),
                   let icon = NSImage(contentsOf: iconPath) {
                    icon.size = NSSize(width: 128, height: 128)
                    alert.icon = icon
                }
                alert.addButton(withTitle: "OK")
                alert.addButton(withTitle: "View on GitHub")
                if alert.runModal() == .alertSecondButtonReturn {
                    NSWorkspace.shared.open(URL(string: "https://github.com/rsml/forge")!)
                }
            }
        }

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
                if let keyWindow = NSApp.keyWindow,
                   keyWindow.identifier?.rawValue == "com_apple_SwiftUI_Settings_window" {
                    keyWindow.close()
                    return
                }
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

            Button("Toggle Mode") {
                NotificationCenter.default.post(name: .forgeToggleMode, object: nil)
            }
            .keyboardShortcut(KeyboardShortcuts.toggleMode.key, modifiers: KeyboardShortcuts.toggleMode.modifiers)

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

            if !ForgeConfigStore.shared.isStackMode {
                Button("Select Tab Right") {
                    guard let session = controller.workspace.activeSession,
                          let windowId = controller.workspace.activeWindowId,
                          let idx = session.windows.firstIndex(where: { $0.id == windowId }),
                          idx < session.windows.count - 1
                    else { return }
                    controller.selectWindow(session.windows[idx + 1])
                }
                .keyboardShortcut(KeyboardShortcuts.selectTabRight.key, modifiers: KeyboardShortcuts.selectTabRight.modifiers)
            }

            if ForgeConfigStore.shared.isStackMode {
                Divider()
                Button("Done") {
                    guard let uuid = controller.attentionManager?.currentWindowUUID else { return }
                    if let (_, window) = controller.workspace.findWindow(byUUID: uuid) {
                        for pane in window.panes { pane.hasBell = false }
                    }
                    controller.attentionManager?.markDone(uuid)
                }
                .keyboardShortcut(KeyboardShortcuts.stackDone.key, modifiers: KeyboardShortcuts.stackDone.modifiers)

                Button("Hide") {
                    guard let uuid = controller.attentionManager?.currentWindowUUID else { return }
                    controller.attentionManager?.hide(uuid)
                }
                .keyboardShortcut(KeyboardShortcuts.stackHide.key, modifiers: KeyboardShortcuts.stackHide.modifiers)

                Button("Move to Back") {
                    guard let uuid = controller.attentionManager?.currentWindowUUID else { return }
                    controller.attentionManager?.moveToBack(uuid)
                }
                .keyboardShortcut(KeyboardShortcuts.stackMoveToBack.key, modifiers: KeyboardShortcuts.stackMoveToBack.modifiers)
            }

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
}

// MARK: - NSColor Helpers

extension NSColor {
    /// Whether this color appears light based on perceived luminance (W3C formula).
    var isLight: Bool {
        guard let rgb = usingColorSpace(.sRGB) else { return false }
        let luminance = 0.299 * rgb.redComponent + 0.587 * rgb.greenComponent + 0.114 * rgb.blueComponent
        return luminance > 0.5
    }
}

// MARK: - App Delegate

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let controller = WorkspaceController(tmux: TmuxAdapter())
    private(set) var attentionManager: AttentionManager!
    private let debugServer = DebugServer()
    private var mainWindow: NSWindow?
    private var appearanceObservation: NSKeyValueObservation?
    private var titleBarOverlay: NSView?
    private var sidebarVisible: Bool
    private var overlayLeadingConstraint: NSLayoutConstraint?
    private var overlayTrailingConstraint: NSLayoutConstraint?
    private var pathLabelLeadingConstraint: NSLayoutConstraint?
    private var splitHButton: NSButton?
    private var splitVButton: NSButton?
    private var listModeButton: NSButton?
    private var isFullScreen = false
    private var branchTrailingToOverlay: NSLayoutConstraint?
    private var branchTrailingToSplitH: NSLayoutConstraint?

    override init() {
        self.sidebarVisible = ForgeConfig.load().uiState?.sidebarVisible ?? true
        super.init()
    }

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
            forName: .forgeConfigChanged, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.updateWindowBackground() }
        }
        NotificationCenter.default.addObserver(
            forName: NSWindow.willEnterFullScreenNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.isFullScreen = true
                self?.updateSplitIconVisibility()
                self?.updateOverlayConstraints()
                // macOS 15.3+ regression: fullscreen titlebar becomes unexpectedly
                // transparent. Disable during fullscreen, restore on exit.
                if #available(macOS 15.3, *) {
                    self?.mainWindow?.titlebarAppearsTransparent = false
                }
            }
        }
        NotificationCenter.default.addObserver(
            forName: NSWindow.didExitFullScreenNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.isFullScreen = false
                self?.measureTitlebarHeight()
                self?.updateSplitIconVisibility()
                self?.reapplyTitleBarStyle()
            }
        }
        NotificationCenter.default.addObserver(
            forName: NSWindow.didBecomeKeyNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.stripTitleBarChrome() }
        }

        NotificationCenter.default.addObserver(
            forName: .forgeWindowTitleChanged, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.updateWindowTitle() }
        }

        NotificationCenter.default.addObserver(
            forName: .forgeToggleMode, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                if ForgeConfigStore.shared.isStackMode {
                    // Stack → List: restore the window that was showing in stack as the active selection
                    if let uuid = self.attentionManager?.currentWindowUUID,
                       let (session, window) = self.controller.workspace.findWindow(byUUID: uuid) {
                        self.controller.workspace.activeSessionId = session.id
                        self.controller.workspace.activeWindowId = window.id
                    }
                    ForgeConfigStore.shared.isStackMode = false
                } else {
                    // List → Stack: promote current window to front of queue if it needs attention
                    if let windowId = self.controller.workspace.activeWindowId,
                       let window = self.controller.workspace.activeSession?.windows.first(where: { $0.id == windowId }),
                       window.needsAttention {
                        self.attentionManager?.promoteToFront(window.uuid)
                    }
                    ForgeConfigStore.shared.isStackMode = true
                }
                self.updateSplitIconVisibility()
                self.updateWindowTitle()
            }
        }

        NotificationCenter.default.addObserver(
            forName: .forgeToggleSidebar, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.sidebarVisible.toggle()
                self?.updateOverlayConstraints()
            }
        }
        NotificationCenter.default.addObserver(
            forName: .forgeConfigChanged, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.updateOverlayConstraints()
                self?.updateSplitIconVisibility()
            }
        }

        // Re-sync titlebar color when system appearance (dark/light mode) changes
        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeOcclusionStateNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.syncAppearance() }
        }
        // Use KVO on effectiveAppearance for immediate dark/light mode response
        appearanceObservation = NSApp.observe(\.effectiveAppearance, options: [.new]) { [weak self] _, _ in
            MainActor.assumeIsolated { self?.syncAppearance() }
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
        measureTitlebarHeight()
        syncAppearance()

        // SwiftUI re-adds title bar chrome during layout passes.
        // In release builds, decoration views appear at unpredictable times,
        // so poll every 100ms for 3 seconds to catch them all.
        let timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.stripTitleBarChrome()
                if self?.titleBarOverlay?.superview == nil {
                    self?.installTitleBarOverlay()
                    self?.updateWindowTitle()
                }
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) { timer.invalidate() }
    }

    private func measureTitlebarHeight() {
        guard let window = mainWindow else { return }
        let height = window.frame.height - window.contentLayoutRect.height
        if height > 0 {
            ForgeConfigStore.shared.titlebarHeight = height
        }
    }

    private func updateWindowBackground() {
        syncAppearance()
    }

    private func reapplyTitleBarStyle() {
        guard let window = mainWindow else { return }
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.titlebarSeparatorStyle = .none
        syncAppearance()
        installTitleBarOverlay()
    }

    private func stripTitleBarChrome() {
        guard let themeFrame = mainWindow?.contentView?.superview else { return }
        Self.hideTitleBarChrome(in: themeFrame)
    }

    /// Hide the NSVisualEffectView and decoration views inside the titlebar container.
    /// Hiding is more resilient than removeFromSuperview across OS updates.
    private static func hideTitleBarChrome(in view: NSView) {
        let name = String(describing: type(of: view))
        if name == "NSTitlebarContainerView" {
            for child in view.subviews {
                let childName = String(describing: type(of: child))
                if childName == "_NSTitlebarDecorationView" || child is NSVisualEffectView {
                    child.isHidden = true
                }
            }
            return
        }
        for sub in view.subviews {
            hideTitleBarChrome(in: sub)
        }
    }

    private func updateWindowTitle() {
        if titleBarOverlay == nil || titleBarOverlay?.superview == nil {
            installTitleBarOverlay()
        }
        guard let overlay = titleBarOverlay else { return }

        let pathLabel = overlay.subviews.first { $0.identifier?.rawValue == "titlePath" } as? NSTextField
        let branchLabel = overlay.subviews.first { $0.identifier?.rawValue == "titleBranch" } as? NSTextField

        // In stack mode, show the path/branch of the window currently at the front of the queue.
        let session: Session?
        if ForgeConfigStore.shared.isStackMode,
           let uuid = attentionManager?.currentWindowUUID,
           let (stackSession, _) = controller.workspace.findWindow(byUUID: uuid) {
            session = stackSession
        } else {
            session = controller.workspace.activeSession
        }
        if let path = session?.path {
            pathLabel?.stringValue = path.replacingOccurrences(of: NSHomeDirectory(), with: "~")
        } else {
            pathLabel?.stringValue = session?.name ?? ""
        }
        branchLabel?.stringValue = controller.gitBranch ?? ""
        updateOverlayConstraints()
    }

    private func installTitleBarOverlay() {
        guard let themeFrame = mainWindow?.contentView?.superview,
              let container = Self.findView(named: "NSTitlebarContainerView", in: themeFrame)
        else { return }

        titleBarOverlay?.removeFromSuperview()

        let overlay = NSView()
        overlay.translatesAutoresizingMaskIntoConstraints = false

        let titleFont = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize, weight: .regular)

        let pathLabel = NSTextField(labelWithString: "")
        pathLabel.font = titleFont
        pathLabel.textColor = .secondaryLabelColor
        pathLabel.lineBreakMode = .byTruncatingMiddle
        pathLabel.translatesAutoresizingMaskIntoConstraints = false
        pathLabel.identifier = NSUserInterfaceItemIdentifier("titlePath")

        let branchLabel = NSTextField(labelWithString: "")
        branchLabel.font = titleFont
        branchLabel.textColor = .secondaryLabelColor
        branchLabel.lineBreakMode = .byTruncatingTail
        branchLabel.translatesAutoresizingMaskIntoConstraints = false
        branchLabel.identifier = NSUserInterfaceItemIdentifier("titleBranch")

        // Split pane buttons
        let splitH = NSButton(image: NSImage(systemSymbolName: "rectangle.split.2x1", accessibilityDescription: "Split Horizontally")!, target: self, action: #selector(splitHorizontalAction))
        splitH.isBordered = false
        splitH.bezelStyle = .accessoryBarAction
        splitH.contentTintColor = .secondaryLabelColor
        splitH.imageScaling = .scaleProportionallyDown
        splitH.toolTip = KeyboardShortcuts.splitHorizontal.tooltip
        splitH.translatesAutoresizingMaskIntoConstraints = false

        let splitV = NSButton(image: NSImage(systemSymbolName: "rectangle.split.1x2", accessibilityDescription: "Split Vertically")!, target: self, action: #selector(splitVerticalAction))
        splitV.isBordered = false
        splitV.bezelStyle = .accessoryBarAction
        splitV.contentTintColor = .secondaryLabelColor
        splitV.imageScaling = .scaleProportionallyDown
        splitV.toolTip = KeyboardShortcuts.splitVertical.tooltip
        splitV.translatesAutoresizingMaskIntoConstraints = false

        splitHButton = splitH
        splitVButton = splitV

        // List mode toggle button (shown only in stack mode, to the left of the path)
        let listBtn = NSButton(image: NSImage(systemSymbolName: "list.bullet", accessibilityDescription: "Switch to List Mode")!, target: self, action: #selector(toggleModeAction))
        listBtn.isBordered = false
        listBtn.bezelStyle = .accessoryBarAction
        listBtn.contentTintColor = .secondaryLabelColor
        listBtn.imageScaling = .scaleProportionallyDown
        listBtn.toolTip = KeyboardShortcuts.toggleMode.tooltip
        listBtn.translatesAutoresizingMaskIntoConstraints = false
        listModeButton = listBtn

        overlay.addSubview(listBtn)
        overlay.addSubview(pathLabel)
        overlay.addSubview(branchLabel)
        overlay.addSubview(splitH)
        overlay.addSubview(splitV)

        pathLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        branchLabel.setContentCompressionResistancePriority(.required, for: .horizontal)

        // In stack mode, list button sits at 78px (after traffic lights), path follows it.
        // In list mode, list button is hidden and path uses pathLabelLeadingConstraint directly.
        NSLayoutConstraint.activate([
            listBtn.leadingAnchor.constraint(equalTo: overlay.leadingAnchor, constant: 74),
            listBtn.centerYAnchor.constraint(equalTo: overlay.centerYAnchor),
            listBtn.widthAnchor.constraint(equalToConstant: 20),
            listBtn.heightAnchor.constraint(equalToConstant: 20),
        ])

        let pathLeading = pathLabel.leadingAnchor.constraint(equalTo: overlay.leadingAnchor, constant: 78)
        pathLabelLeadingConstraint = pathLeading

        let branchToOverlay = branchLabel.trailingAnchor.constraint(equalTo: overlay.trailingAnchor, constant: -12)
        let branchToSplitH = branchLabel.trailingAnchor.constraint(lessThanOrEqualTo: splitH.leadingAnchor, constant: -8)
        branchTrailingToOverlay = branchToOverlay
        branchTrailingToSplitH = branchToSplitH

        NSLayoutConstraint.activate([
            pathLeading,
            pathLabel.centerYAnchor.constraint(equalTo: overlay.centerYAnchor),
            branchLabel.centerYAnchor.constraint(equalTo: overlay.centerYAnchor),
            pathLabel.trailingAnchor.constraint(lessThanOrEqualTo: branchLabel.leadingAnchor, constant: -8),

            splitH.widthAnchor.constraint(equalToConstant: 20),
            splitH.heightAnchor.constraint(equalToConstant: 20),
            splitH.centerYAnchor.constraint(equalTo: overlay.centerYAnchor),

            splitV.leadingAnchor.constraint(equalTo: splitH.trailingAnchor, constant: 2),
            splitV.widthAnchor.constraint(equalToConstant: 20),
            splitV.heightAnchor.constraint(equalToConstant: 20),
            splitV.centerYAnchor.constraint(equalTo: overlay.centerYAnchor),
            splitV.trailingAnchor.constraint(equalTo: overlay.trailingAnchor, constant: -12),
        ])

        container.addSubview(overlay)
        let leading = overlay.leadingAnchor.constraint(equalTo: container.leadingAnchor)
        let trailing = overlay.trailingAnchor.constraint(equalTo: container.trailingAnchor)
        overlayLeadingConstraint = leading
        overlayTrailingConstraint = trailing

        NSLayoutConstraint.activate([
            leading,
            trailing,
            overlay.topAnchor.constraint(equalTo: container.topAnchor),
            overlay.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])

        titleBarOverlay = overlay
        updateOverlayConstraints()
        updateSplitIconVisibility()

    }

    private func updateOverlayConstraints() {
        if isFullScreen {
            overlayLeadingConstraint?.constant = 0
            overlayTrailingConstraint?.constant = 0
            pathLabelLeadingConstraint?.constant = 78
            return
        }

        // In stack mode: no sidebar, show list-mode button, path starts after it
        let isStack = ForgeConfigStore.shared.isStackMode
        listModeButton?.isHidden = !isStack
        if isStack {
            overlayLeadingConstraint?.constant = 0
            overlayTrailingConstraint?.constant = 0
            pathLabelLeadingConstraint?.constant = 98  // 74 (button leading) + 20 (button) + 4 (gap)
            return
        }

        let position = ForgeConfigStore.shared.config.general?.sidebarPosition ?? "left"
        let effectivelyVisible = sidebarVisible && !controller.workspace.sessions.isEmpty
        let sidebarTotal: CGFloat = effectivelyVisible ? ForgeConfigStore.shared.sidebarWidth + 1 : 0

        if position == "right" {
            overlayLeadingConstraint?.constant = 0
            overlayTrailingConstraint?.constant = -sidebarTotal
            pathLabelLeadingConstraint?.constant = 78
        } else {
            overlayLeadingConstraint?.constant = sidebarTotal
            overlayTrailingConstraint?.constant = 0
            pathLabelLeadingConstraint?.constant = effectivelyVisible ? 12 : 78
        }
    }

    private func updateSplitIconVisibility() {
        // Hide split icons in stack mode — the stack toolbar handles actions
        if ForgeConfigStore.shared.isStackMode {
            splitHButton?.isHidden = true
            splitVButton?.isHidden = true
            branchTrailingToSplitH?.isActive = false
            branchTrailingToOverlay?.isActive = true
            return
        }
        let tabPos = ForgeConfigStore.shared.config.general?.tabBarPosition ??
                     ForgeConfigStore.shared.config.terminal?.tabBarPosition ??
                     ForgeConfigStore.shared.config.appearance?.tabBarPosition ?? "top"
        let show = (tabPos != "bottom" && !isFullScreen)
        splitHButton?.isHidden = !show
        splitVButton?.isHidden = !show
        branchTrailingToSplitH?.isActive = show
        branchTrailingToOverlay?.isActive = !show
    }

    @objc private func splitHorizontalAction() { controller.splitPane(direction: .horizontal) }
    @objc private func splitVerticalAction() { controller.splitPane(direction: .vertical) }
    @objc private func toggleModeAction() {
        NotificationCenter.default.post(name: .forgeToggleMode, object: nil)
    }

    private static func findView(named name: String, in view: NSView) -> NSView? {
        if String(describing: type(of: view)) == name { return view }
        for sub in view.subviews {
            if let found = findView(named: name, in: sub) { return found }
        }
        return nil
    }

    private func syncAppearance() {
        guard let window = mainWindow else { return }
        if let theme = ForgeConfigStore.shared.resolvedTheme {
            let bgColor = NSColor(theme.background)
            window.backgroundColor = bgColor
            // Set window appearance to match background luminance so
            // traffic lights and other chrome adapt correctly
            window.appearance = bgColor.isLight
                ? NSAppearance(named: .aqua)
                : NSAppearance(named: .darkAqua)
        } else {
            window.backgroundColor = .windowBackgroundColor
            window.appearance = nil
        }
        stripTitleBarChrome()
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
