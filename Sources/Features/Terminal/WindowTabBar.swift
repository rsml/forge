import SwiftUI
import ForgeCore

struct WindowTabBar: View {
    @Environment(ForgeConfigStore.self) private var configStore
    var project: Project
    var sidebarVisible: Bool = true
    var sidebarPosition: String = "left"
    var isFullScreen: Bool = false
    var onToggleSidebar: () -> Void = {}
    @Environment(WorkspaceController.self) var controller
    @Environment(AttentionManager.self) var attention
    @Environment(AppState.self) private var appState

    private var tabBarOnBottom: Bool {
        let pos = configStore.config.general?.tabBarPosition ??
                  configStore.config.terminal?.tabBarPosition ??
                  configStore.config.appearance?.tabBarPosition ?? "top"
        return pos == "bottom"
    }

    var body: some View {
        // Tab bar only (title bar is in ProjectDetailView)
        HStack(spacing: 0) {
                // Show sidebar toggle when sidebar is hidden (left position)
                if !sidebarVisible && sidebarPosition != "right" {
                    IconButton(systemName: "sidebar.left") { onToggleSidebar() }
                        .frame(width: 40, height: 28)
                        .tooltip(KeyboardShortcuts.toggleSidebar)
                }

                ScrollView(.horizontal, showsIndicators: false) {
                    ReorderableStack(project.tabs, axis: .horizontal, spacing: 1) { tab, isDragging in
                        if appState.renamingTabId == tab.id {
                            InlineRenameField(
                                text: Binding(
                                    get: { appState.renameText },
                                    set: { appState.renameText = $0 }
                                ),
                                font: .system(.caption, weight: .regular),
                                onCancel: { appState.renamingTabId = nil },
                                onCommit: { appState.commitTabRename(tab) }
                            )
                            .fixedSize()
                            .frame(height: 28)
                        } else {
                            WindowTab(
                                tab: tab,
                                isActive: tab.id == controller.workspace.activeTabId,
                                tabIndex: project.tabs.firstIndex(where: { $0.id == tab.id }).map { $0 + 1 } ?? 0,
                                indicatorOnTop: tabBarOnBottom,
                                notificationsDisabled: attention.isHidden(tab.uuid)
                            )
                            .onTapGesture {
                                controller.selectTab(tab)
                            }
                            .contextMenu {
                                PaneContextMenu(
                                    controller: controller,
                                    appState: appState,
                                    attention: attention,
                                    project: project,
                                    tab: tab,
                                    pane: nil
                                )
                            }
                        }
                    } onReorder: { from, to in
                        controller.reorderTab(in: project, from: from, to: to)
                    }
                    .padding(.horizontal, 4)
                }
                .fixedSize(horizontal: true, vertical: false)

                Color.clear
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .contentShape(Rectangle())
                    .onTapGesture(count: 2) {
                        controller.addTab(in: project)
                    }
                    .contextMenu {
                        Button("New Tab") {
                            controller.addTab(in: project)
                        }
                        .keyboardShortcut(KeyboardShortcuts.newTab.key, modifiers: KeyboardShortcuts.newTab.modifiers)
                        Button("New Browser Tab") {
                            controller.addBrowserTab(in: project)
                        }
                        .keyboardShortcut("t", modifiers: [.command, .option])
                    }

                // Only show split icons in tab bar when tabs are on bottom OR fullscreen
                // (when tabs on top + windowed, they appear in the titlebar instead)
                if tabBarOnBottom || isFullScreen {
                    IconButton(systemName: "rectangle.split.2x1") {
                        controller.splitPane(direction: .horizontal)
                    }
                    .frame(width: 40, height: 28)
                    .tooltip(KeyboardShortcuts.splitHorizontal)

                    IconButton(systemName: "rectangle.split.1x2") {
                        controller.splitPane(direction: .vertical)
                    }
                    .frame(width: 40, height: 28)
                    .tooltip(KeyboardShortcuts.splitVertical)
                }

                // Show sidebar toggle when sidebar is hidden (right position)
                if !sidebarVisible && sidebarPosition == "right" {
                    IconButton(systemName: "sidebar.right") { onToggleSidebar() }
                        .frame(width: 40, height: 28)
                        .tooltip(KeyboardShortcuts.toggleSidebar)
                }
            }
        .frame(height: 28)
        .background(configStore.resolvedTheme?.background.color ?? Color(nsColor: .controlBackgroundColor))
    }
}


struct WindowTab: View {
    @Environment(ForgeConfigStore.self) private var configStore
    @Environment(ModifierKeyMonitor.self) private var modifiers
    var tab: ForgeCore.Tab
    let isActive: Bool
    var tabIndex: Int = 0
    var indicatorOnTop: Bool = false
    var notificationsDisabled: Bool = false
    @State private var isHovered = false

    private var secondaryFont: Font { configStore.secondaryFont }

    var body: some View {

        VStack(spacing: 0) {
            if indicatorOnTop {
                // Active tab indicator — flush to top
                RoundedRectangle(cornerRadius: 1)
                    .fill(isActive ? configStore.tabHighlightColor.opacity(0.6) : Color.clear)
                    .frame(height: 2)
                    .padding(.horizontal, 6)
            }

            HStack(spacing: 4) {
                if modifiers.commandPressed && tabIndex >= 1 && tabIndex <= 9 {
                    Text("\(tabIndex)")
                        .font(.system(.caption, weight: .medium))
                        .foregroundStyle(configStore.tabHighlightColor)
                        .frame(width: 14)
                }
                AttentionDot(needsAttention: tab.needsAttention && !notificationsDisabled)
                Text(tab.name)
                    .font(secondaryFont)
                    .foregroundStyle((isActive || isHovered) ? .primary : .secondary)
                    .lineLimit(1)
            }
            .padding(.horizontal, 10)
            .frame(maxHeight: .infinity)
            .offset(y: indicatorOnTop ? -1 : 1)

            if !indicatorOnTop {
                // Active tab indicator — flush to bottom
                RoundedRectangle(cornerRadius: 1)
                    .fill(isActive ? configStore.tabHighlightColor.opacity(0.6) : Color.clear)
                    .frame(height: 2)
                    .padding(.horizontal, 6)
            }
        }
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
    }
}
