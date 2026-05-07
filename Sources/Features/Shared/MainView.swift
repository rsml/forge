import SwiftUI
import ForgeCore

struct MainView: View {
    @Environment(ForgeConfigStore.self) private var configStore
    @Environment(WorkspaceController.self) var controller
    @Environment(AppState.self) private var appState
    @Environment(CommandRegistry.self) private var commandRegistry
    @Environment(ModifierKeyMonitor.self) private var modifierKeyMonitor
    @Environment(NotificationToastState.self) private var toastState
    @State private var sidebarWidth: CGFloat = 160

    @State private var dragStartWidth: CGFloat? = nil

    private static let minSidebarWidth: CGFloat = 120
    private static let maxSidebarWidth: CGFloat = 400

    private var sidebarPosition: String {
        configStore.config.general?.sidebarPosition ?? "left"
    }

    private var sidebarBackground: some View {
        ZStack {
            if let theme = configStore.resolvedTheme {
                theme.background.color
                Color.white.opacity(0.06)  // slightly lighter than terminal
            } else {
                Color(nsColor: .windowBackgroundColor)
            }
        }
    }

    private var themeForeground: Color? {
        configStore.resolvedTheme?.foreground.color
    }

    private var showSidebar: Bool {
        appState.sidebarVisible && !controller.workspace.projects.isEmpty
    }

    var body: some View {
        Group {
            if configStore.isStackMode {
                StackView()
            } else {
                HStack(spacing: 0) {
                    if sidebarPosition == "right" {
                        detailContent

                        if showSidebar {
                            sidebarDivider
                            sidebarContent
                                .frame(width: sidebarWidth)
                                .background { sidebarBackground }
                                .zIndex(2)
                        }
                    } else {
                        if showSidebar {
                            sidebarContent
                                .frame(width: sidebarWidth)
                                .background { sidebarBackground }
                                .zIndex(2)
                            sidebarDivider
                        }

                        detailContent
                    }
                }
            }
        }
        .modifier(ModalOverlays())
        .modifier(NotificationToastOverlay(state: toastState))
        .foregroundStyle(themeForeground ?? Color.primary)
        .ignoresSafeArea()
        .onAppear {
            commandRegistry.setup(controller: controller, appState: appState)
            modifierKeyMonitor.onOptionNumber = { n in
                let sessions = controller.workspace.projects
                guard sessions.count >= n else { return }
                controller.selectProject(sessions[n - 1])
            }
        }
        .onChange(of: controller.workspace.projects.count) {
            autoFitSidebarWidth()
        }
        .onChange(of: sidebarWidth) {
            configStore.sidebarWidth = sidebarWidth
            NotificationCenter.default.post(name: .forgeWindowTitleChanged, object: nil)
        }
        .onChange(of: appState.sidebarVisible) {
            NotificationCenter.default.post(name: .forgeWindowTitleChanged, object: nil)
        }
    }

    @ViewBuilder
    private var sidebarContent: some View {
        SidebarProjectList(
            position: sidebarPosition,
            onToggleSidebar: { appState.dispatch(.toggleSidebar) }
        )
    }

    @ViewBuilder
    private var detailContent: some View {
        VStack(spacing: 0) {
            if let project = controller.workspace.activeProject {
                ProjectDetailView(
                    project: project,
                    sidebarVisible: appState.sidebarVisible,
                    onToggleSidebar: { appState.dispatch(.toggleSidebar) }
                )
            } else {
                VStack(spacing: 8) {
                    Spacer()
                    Button {
                        appState.dispatch(.showProjectPicker)
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
                    .frame(width: 16)
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
                            NSCursor.resizeLeftRight.set()
                        } else {
                            NSCursor.arrow.set()
                        }
                    }
            }
            .zIndex(1)
    }

    /// Grow sidebar to fit the longest project name, clamped to min/max.
    private func autoFitSidebarWidth() {
        let font = NSFont.systemFont(ofSize: 13, weight: .medium)
        let maxName = controller.workspace.projects
            .map { ($0.name as NSString).size(withAttributes: [.font: font]).width }
            .max() ?? 0
        // name + chevron(16) + dot(8) + spacing(6+6) + horizontal padding(2*2)
        let needed = maxName + 42
        if needed > sidebarWidth {
            sidebarWidth = min(needed, Self.maxSidebarWidth)
        }
    }
}
