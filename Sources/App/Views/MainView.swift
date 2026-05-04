import SwiftUI

struct MainView: View {
    @Environment(WorkspaceController.self) var controller
    @State private var sidebarWidth: CGFloat = 160
    @State private var sidebarVisible = ForgeConfig.load().uiState?.sidebarVisible ?? true
    @State private var showCommandPalette = false

    var body: some View {
        HStack(spacing: 0) {
            // Sidebar
            if sidebarVisible {
                SidebarView(onToggleSidebar: {
                    withAnimation(.easeInOut(duration: 0.2)) { sidebarVisible.toggle() }
                    controller.saveUIState(sidebarVisible: sidebarVisible)
                })
                    .frame(width: sidebarWidth)
                    .background(Color(nsColor: .windowBackgroundColor).opacity(0.5))

                // Divider
                Rectangle()
                    .fill(Color(nsColor: .separatorColor))
                    .frame(width: 1)
            }

            // Detail
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
        .overlay {
            if showCommandPalette {
                ZStack {
                    Color.black.opacity(0.3)
                        .ignoresSafeArea()
                        .onTapGesture { showCommandPalette = false }

                    VStack {
                        CommandPalette(isPresented: $showCommandPalette)
                            .padding(.top, 80)
                        Spacer()
                    }
                }
            }
        }
        .ignoresSafeArea()
        .onAppear {
            configureWindow()
            CommandRegistry.shared.setup(controller: controller)
        }
        .onReceive(NotificationCenter.default.publisher(for: .forgeCommandPalette)) { _ in
            showCommandPalette.toggle()
        }
        .onReceive(NotificationCenter.default.publisher(for: .forgeToggleSidebar)) { _ in
            withAnimation(.easeInOut(duration: 0.2)) { sidebarVisible.toggle() }
            controller.saveUIState(sidebarVisible: sidebarVisible)
        }
    }

    private func configureWindow() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            guard let window = NSApp.windows.first(where: { $0.isVisible }) else { return }
            Self.applyWindowStyle(window)
            NotificationCenter.default.addObserver(
                forName: NSWindow.didExitFullScreenNotification,
                object: window,
                queue: .main
            ) { notification in
                if let w = notification.object as? NSWindow {
                    Self.applyWindowStyle(w)
                }
            }
        }
    }

    @MainActor private static func applyWindowStyle(_ window: NSWindow) {
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.styleMask.insert(.fullSizeContentView)
        window.isMovableByWindowBackground = false
    }
}
