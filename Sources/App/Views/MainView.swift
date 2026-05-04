import SwiftUI

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

    var body: some View {
        HStack(spacing: 0) {
            if sidebarPosition == "right" {
                detailContent

                if sidebarVisible {
                    Rectangle().fill(Color(nsColor: .separatorColor)).frame(width: 1)
                    sidebarContent
                        .frame(width: sidebarWidth)
                        .background(Color(nsColor: .windowBackgroundColor).opacity(0.5))
                }
            } else {
                if sidebarVisible {
                    sidebarContent
                        .frame(width: sidebarWidth)
                        .background(Color(nsColor: .windowBackgroundColor).opacity(0.5))
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
