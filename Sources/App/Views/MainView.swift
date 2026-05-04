import SwiftUI

/// Configures the host NSWindow from within the SwiftUI view hierarchy.
/// Directly manipulates the NSWindow title bar view hierarchy to eliminate
/// the native macOS title bar chrome (background material/vibrancy) while
/// keeping traffic light buttons. This is how Chrome and iTerm2 do it.
struct WindowConfigurator: NSViewRepresentable {
    let backgroundColor: NSColor

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        view.setFrameSize(.zero)
        DispatchQueue.main.async { self.configure(view.window) }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        configure(nsView.window)
    }

    private func configure(_ window: NSWindow?) {
        guard let window else { return }
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        if !window.styleMask.contains(.fullSizeContentView) {
            window.styleMask.insert(.fullSizeContentView)
        }
        window.titlebarSeparatorStyle = .none
        window.isMovableByWindowBackground = false
        window.backgroundColor = backgroundColor

        // Walk the window's view hierarchy and neutralize title bar background
        guard let themeFrame = window.contentView?.superview else { return }
        stripTitleBarBackground(themeFrame, bgColor: backgroundColor)
    }

    /// Find the NSTitlebarContainerView and hide its _NSTitlebarDecorationView.
    /// The decoration view renders the dark background behind traffic lights.
    /// NSTitlebarView (sibling) contains the traffic light buttons and is kept visible.
    private func stripTitleBarBackground(_ view: NSView, bgColor: NSColor, depth: Int = 0) {
        let className = String(describing: type(of: view))

        if className == "NSTitlebarContainerView" {
            for child in view.subviews {
                let childClass = String(describing: type(of: child))
                if childClass == "_NSTitlebarDecorationView" {
                    child.isHidden = true
                }
            }
            return
        }

        for subview in view.subviews {
            stripTitleBarBackground(subview, bgColor: bgColor, depth: depth + 1)
        }
    }
}

struct MainView: View {
    @Environment(WorkspaceController.self) var controller
    @State private var sidebarWidth: CGFloat = 160
    @State private var sidebarVisible = ForgeConfig.load().uiState?.sidebarVisible ?? true
    @State private var showCommandPalette = false
    @State private var showNewProject = false
    @State private var showNotifications = false

    private var sidebarPosition: String {
        ForgeConfigStore.shared.config.general?.sidebarPosition ?? "left"
    }

    private var sidebarBackground: some View {
        ZStack {
            if let theme = ForgeConfigStore.shared.resolvedTheme {
                theme.background
                Color.white.opacity(0.06)  // slightly lighter than terminal
            } else {
                Color(nsColor: .windowBackgroundColor)
            }
        }
    }

    private var themeForeground: Color? {
        ForgeConfigStore.shared.resolvedTheme?.foreground
    }

    var body: some View {
        HStack(spacing: 0) {
            if sidebarPosition == "right" {
                detailContent

                if sidebarVisible {
                    Rectangle().fill(Color(nsColor: .separatorColor)).frame(width: 1)
                    sidebarContent
                        .frame(width: sidebarWidth)
                        .background(sidebarBackground)
                }
            } else {
                if sidebarVisible {
                    sidebarContent
                        .frame(width: sidebarWidth)
                        .background(sidebarBackground)
                    Rectangle().fill(Color(nsColor: .separatorColor)).frame(width: 1)
                }

                detailContent
            }
        }
        .overlay {
            if showCommandPalette {
                ModalContainer(isPresented: $showCommandPalette, width: 500, maxHeight: 400) {
                    CommandPalette(isPresented: $showCommandPalette)
                }
            }
        }
        .overlay {
            if showNewProject {
                ModalContainer(isPresented: $showNewProject, width: 520, maxHeight: 480) {
                    ProjectPickerView(onDismiss: { showNewProject = false })
                }
            }
        }
        .overlay {
            if showNotifications {
                ModalContainer(isPresented: $showNotifications, width: 380, maxHeight: 440) {
                    NotificationPanel(onDismiss: { showNotifications = false })
                }
            }
        }
        .background(
            WindowConfigurator(backgroundColor: {
                if let theme = ForgeConfigStore.shared.resolvedTheme {
                    return NSColor(theme.background)
                }
                return .windowBackgroundColor
            }())
        )
        .foregroundStyle(themeForeground ?? Color.primary)
        .ignoresSafeArea()
        .onAppear {
            CommandRegistry.shared.setup(controller: controller)
            ModifierKeyMonitor.shared.onOptionNumber = { n in
                let sessions = controller.workspace.sessions
                guard sessions.count >= n else { return }
                controller.selectSession(sessions[n - 1])
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .forgeCommandPalette)) { _ in
            showCommandPalette.toggle()
        }
        .onReceive(NotificationCenter.default.publisher(for: .forgeToggleSidebar)) { _ in
            withAnimation(.easeInOut(duration: 0.2)) { sidebarVisible.toggle() }
            controller.saveUIState(sidebarVisible: sidebarVisible)
        }
        .onReceive(NotificationCenter.default.publisher(for: .forgeNewProject)) { _ in
            showNewProject = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .forgeNotifications)) { _ in
            showNotifications = true
        }
    }

    @ViewBuilder
    private var sidebarContent: some View {
        SidebarView(
            position: sidebarPosition,
            onToggleSidebar: {
                withAnimation(.easeInOut(duration: 0.2)) { sidebarVisible.toggle() }
                controller.saveUIState(sidebarVisible: sidebarVisible)
            }
        )
    }

    @ViewBuilder
    private var detailContent: some View {
        VStack(spacing: 0) {
            if let session = controller.workspace.activeSession {
                SessionDetailView(
                    session: session,
                    sidebarVisible: sidebarVisible,
                    onToggleSidebar: {
                        withAnimation(.easeInOut(duration: 0.2)) { sidebarVisible.toggle() }
                        controller.saveUIState(sidebarVisible: sidebarVisible)
                    }
                )
            } else {
                VStack {
                    Spacer()
                    Text("Click + to open a project")
                        .foregroundStyle(.secondary)
                        .font(.body)
                    Spacer()
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
