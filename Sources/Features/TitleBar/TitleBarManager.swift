import AppKit
import ForgeCore

/// Manages the custom title bar overlay: path/branch labels, split buttons, mode toggle,
/// chrome stripping, fullscreen handling, and appearance sync.
@MainActor
final class TitleBarManager: NSObject {
    let window: NSWindow
    let controller: WorkspaceController
    let attentionManager: AttentionManager
    let config: ForgeConfigStore

    var titleBarOverlay: NSView?
    var overlayLeadingConstraint: NSLayoutConstraint?
    var overlayTrailingConstraint: NSLayoutConstraint?
    var pathLabelLeadingConstraint: NSLayoutConstraint?
    var splitHButton: NSButton?
    var splitVButton: NSButton?
    var listModeButton: NSButton?
    var isFullScreen = false
    var branchTrailingToOverlay: NSLayoutConstraint?
    var branchTrailingToSplitH: NSLayoutConstraint?
    var sidebarVisible: Bool

    init(window: NSWindow, controller: WorkspaceController, attentionManager: AttentionManager, config: ForgeConfigStore) {
        self.window = window
        self.controller = controller
        self.attentionManager = attentionManager
        self.config = config
        self.sidebarVisible = ForgeConfig.load().uiState?.sidebarVisible ?? true
        super.init()
        registerObservers()
        startChromeStrippingTimer()
    }

    // MARK: - Setup

    private func startChromeStrippingTimer() {
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

    private func registerObservers() {
        NotificationCenter.default.addObserver(
            forName: NSWindow.willEnterFullScreenNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.isFullScreen = true
                self?.updateSplitIconVisibility()
                self?.updateOverlayConstraints()
                if #available(macOS 15.3, *) {
                    self?.window.titlebarAppearsTransparent = false
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
                self?.syncAppearance()
                self?.updateOverlayConstraints()
                self?.updateSplitIconVisibility()
            }
        }
    }

    // MARK: - Public

    func measureTitlebarHeight() {
        let height = window.frame.height - window.contentLayoutRect.height
        if height > 0 {
            config.titlebarHeight = height
        }
    }

    func syncAppearance() {
        if let theme = config.resolvedTheme {
            let bgColor = NSColor(theme.background)
            window.backgroundColor = bgColor
            window.appearance = bgColor.isLight
                ? NSAppearance(named: .aqua)
                : NSAppearance(named: .darkAqua)
        } else {
            window.backgroundColor = .windowBackgroundColor
            window.appearance = nil
        }
        stripTitleBarChrome()
    }

    func updateSplitIconVisibility() {
        if config.isStackMode {
            splitHButton?.isHidden = true
            splitVButton?.isHidden = true
            branchTrailingToSplitH?.isActive = false
            branchTrailingToOverlay?.isActive = true
            return
        }
        let tabPos = config.config.general?.tabBarPosition ??
                     config.config.terminal?.tabBarPosition ??
                     config.config.appearance?.tabBarPosition ?? "top"
        let show = (tabPos != "bottom" && !isFullScreen)
        splitHButton?.isHidden = !show
        splitVButton?.isHidden = !show
        branchTrailingToSplitH?.isActive = show
        branchTrailingToOverlay?.isActive = !show
    }

    func updateWindowTitle() {
        if titleBarOverlay == nil || titleBarOverlay?.superview == nil {
            installTitleBarOverlay()
        }
        guard let overlay = titleBarOverlay else { return }

        let pathLabel = overlay.subviews.first { $0.identifier?.rawValue == "titlePath" } as? NSTextField
        let branchLabel = overlay.subviews.first { $0.identifier?.rawValue == "titleBranch" } as? NSTextField

        let project: Project?
        if config.isStackMode,
           let uuid = attentionManager.currentTabUUID,
           let (stackSession, _) = controller.workspace.findTab(byUUID: uuid) {
            project = stackSession
        } else {
            project = controller.workspace.activeProject
        }
        if let path = project?.path {
            pathLabel?.stringValue = path.replacingOccurrences(of: NSHomeDirectory(), with: "~")
        } else {
            pathLabel?.stringValue = project?.name ?? ""
        }
        branchLabel?.stringValue = controller.gitBranch ?? ""
        updateOverlayConstraints()
    }

    func updateOverlayConstraints() {
        if isFullScreen {
            overlayLeadingConstraint?.constant = 0
            overlayTrailingConstraint?.constant = 0
            pathLabelLeadingConstraint?.constant = 78
            return
        }

        let isStack = config.isStackMode
        listModeButton?.isHidden = !isStack
        if isStack {
            overlayLeadingConstraint?.constant = 0
            overlayTrailingConstraint?.constant = 0
            pathLabelLeadingConstraint?.constant = 118
            return
        }

        let position = config.config.general?.sidebarPosition ?? "left"
        let effectivelyVisible = sidebarVisible && !controller.workspace.projects.isEmpty
        let sidebarTotal: CGFloat = effectivelyVisible ? config.sidebarWidth + 1 : 0

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

    func reapplyTitleBarStyle() {
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.titlebarSeparatorStyle = .none
        syncAppearance()
        installTitleBarOverlay()
    }

    // MARK: - Actions

    @objc func splitHorizontalAction() { controller.splitPane(direction: .horizontal) }
    @objc func splitVerticalAction() { controller.splitPane(direction: .vertical) }
    @objc func toggleModeAction() {
        NotificationCenter.default.post(name: .forgeToggleMode, object: nil)
    }
}
