import SwiftUI

struct MainView: View {
    @Environment(WorkspaceController.self) var controller
    @State private var sidebarWidth: CGFloat = 160
    @State private var sidebarVisible = ForgeConfig.load().uiState?.sidebarVisible ?? true
    @State private var showCommandPalette = false
    @State private var showNewProject = false
    @State private var showNotifications = false

    @State private var dragStartWidth: CGFloat? = nil

    private static let minSidebarWidth: CGFloat = 120
    private static let maxSidebarWidth: CGFloat = 400

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

    private var showSidebar: Bool {
        sidebarVisible && !controller.workspace.sessions.isEmpty
    }

    var body: some View {
        HStack(spacing: 0) {
            if sidebarPosition == "right" {
                detailContent

                if showSidebar {
                    sidebarDivider
                    sidebarContent
                        .frame(width: sidebarWidth)
                        .background(sidebarBackground)
                }
            } else {
                if showSidebar {
                    sidebarContent
                        .frame(width: sidebarWidth)
                        .background(sidebarBackground)
                    sidebarDivider
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
        .onChange(of: controller.workspace.sessions.count) {
            autoFitSidebarWidth()
        }
        .onChange(of: sidebarWidth) {
            ForgeConfigStore.shared.sidebarWidth = sidebarWidth
            NotificationCenter.default.post(name: .forgeWindowTitleChanged, object: nil)
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
                VStack(spacing: 8) {
                    Spacer()
                    Button {
                        NotificationCenter.default.post(name: .forgeNewProject, object: nil)
                    } label: {
                        VStack(spacing: 2) {
                            Text("Open a New Project")
                            Text(KeyboardShortcuts.newProject.hint)
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .buttonStyle(.bordered)
                    Spacer()
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var sidebarDivider: some View {
        Color.clear
            .frame(width: 1)
            .overlay {
                Color.clear
                    .frame(width: 30)
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 1, coordinateSpace: .global)
                            .onChanged { value in
                                if dragStartWidth == nil { dragStartWidth = sidebarWidth }
                                let base = dragStartWidth!
                                let delta = sidebarPosition == "right"
                                    ? -value.translation.width
                                    : value.translation.width
                                sidebarWidth = min(max(base + delta, Self.minSidebarWidth), Self.maxSidebarWidth)
                            }
                            .onEnded { _ in
                                dragStartWidth = nil
                            }
                    )
                    .onHover { hovering in
                        if hovering {
                            NSCursor.resizeLeftRight.push()
                        } else {
                            NSCursor.pop()
                        }
                    }
            }
            .zIndex(1)
    }

    /// Grow sidebar to fit the longest session name, clamped to min/max.
    private func autoFitSidebarWidth() {
        let font = NSFont.systemFont(ofSize: 13, weight: .medium)
        let maxName = controller.workspace.sessions
            .map { ($0.name as NSString).size(withAttributes: [.font: font]).width }
            .max() ?? 0
        // name + chevron(16) + dot(8) + spacing(6+6) + horizontal padding(2*2)
        let needed = maxName + 42
        if needed > sidebarWidth {
            sidebarWidth = min(needed, Self.maxSidebarWidth)
        }
    }
}
