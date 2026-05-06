import SwiftUI
import ForgeCore

/// Observable UI state shared across views. Commands translate to state transitions.
/// Injected via @Environment. Views bind directly to properties.
@Observable @MainActor
final class AppState {
    // Modal presentation — mutually exclusive
    var activeModal: Modal? = nil
    enum Modal: Equatable {
        case projectPicker
        case commandPalette
        case notifications
    }

    // Sidebar
    var sidebarVisible: Bool
    var expandedProjectIds: Set<String> = []

    // Inline rename (nil = not renaming)
    var renamingTabId: String? = nil
    var renamingProjectId: String? = nil

    // Stack action trigger — StackView observes this to run animations
    var pendingStackAction: WorkspaceController.StackDismissAction? = nil

    private weak var controller: WorkspaceController?
    private weak var titleBarManager: TitleBarManager?
    private weak var attentionManager: AttentionManager?
    private weak var config: ForgeConfigStore?

    init(sidebarVisible: Bool = true) {
        self.sidebarVisible = sidebarVisible
    }

    func bind(controller: WorkspaceController, titleBarManager: TitleBarManager?, attentionManager: AttentionManager?, config: ForgeConfigStore) {
        self.controller = controller
        self.titleBarManager = titleBarManager
        self.attentionManager = attentionManager
        self.config = config
    }

    func dispatch(_ command: AppCommand) {
        guard let controller, let config else { return }

        switch command {
        // Modals
        case .showProjectPicker:   activeModal = .projectPicker
        case .showCommandPalette:  activeModal = .commandPalette
        case .showNotifications:   activeModal = .notifications
        case .dismissModal:        activeModal = nil

        // Sidebar
        case .toggleSidebar:
            sidebarVisible.toggle()
            controller.saveUIState(sidebarVisible: sidebarVisible)
        case .collapseAll:
            expandedProjectIds.removeAll()
            let names: [String] = []
            controller.saveUIState(expandedProjectNames: names)
        case .expandAll:
            expandedProjectIds = Set(controller.workspace.projects.map(\.id))
            let names = controller.workspace.projects.map(\.name)
            controller.saveUIState(expandedProjectNames: names)

        // Rename
        case .renameTab:
            renamingProjectId = nil
            if let tabId = controller.workspace.activeTabId,
               let project = controller.workspace.activeProject,
               let tab = project.tabs.first(where: { $0.id == tabId }) {
                renamingTabId = tab.id
            }
        case .renameProject:
            renamingTabId = nil
            if let project = controller.workspace.activeProject {
                renamingProjectId = project.id
            }

        // Mode toggle — domain logic
        case .toggleMode:
            if config.isStackMode {
                if let uuid = attentionManager?.currentTabUUID,
                   let (project, tab) = controller.workspace.findTab(byUUID: uuid) {
                    controller.workspace.activeProjectId = project.id
                    controller.workspace.activeTabId = tab.id
                }
                config.isStackMode = false
            } else {
                if let tabId = controller.workspace.activeTabId,
                   let tab = controller.workspace.activeProject?.tabs.first(where: { $0.id == tabId }),
                   tab.needsAttention {
                    attentionManager?.promoteToFront(tab.uuid)
                }
                config.isStackMode = true
                if let uuid = attentionManager?.currentTabUUID,
                   let (_, tab) = controller.workspace.findTab(byUUID: uuid) {
                    controller.selectTab(tab)
                }
            }
            titleBarManager?.updateSplitIconVisibility()
            titleBarManager?.updateWindowTitle()
            DispatchQueue.main.async { [weak self] in
                self?.titleBarManager?.updateOverlayConstraints()
            }

        // Tab movement
        case .moveTabLeft:  controller.swapTab(offset: -1)
        case .moveTabRight: controller.swapTab(offset: 1)

        // Stack actions — set trigger for StackView to animate
        case .stackDone:       pendingStackAction = .done
        case .stackHide:       pendingStackAction = .hide
        case .stackMoveToBack: pendingStackAction = .moveToBack
        }
    }
}
