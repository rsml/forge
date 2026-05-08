import SwiftUI
import ForgeCore

struct SidebarProjectRow: View {
    var project: Project
    var isActive: Bool
    var activeTabId: String?
    @Binding var isExpanded: Bool
    var onTabDraggedOut: ((ForgeCore.Tab, Edge) -> Void)?
    var projectIndex: Int = 0

    @Environment(ForgeConfigStore.self) private var configStore
    @Environment(WorkspaceController.self) var controller
    @Environment(AppState.self) private var appState
    @Environment(AttentionManager.self) var attention
    @Environment(ModifierKeyMonitor.self) private var modifiers
    @State private var isHeaderHovered = false
    @State private var isChevronHovered = false
    @State private var hoveredTabId: String?

    private var isRenaming: Bool { appState.renamingProjectId == project.id }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            projectHeader

            if isExpanded {
                tabList
            }
        }
    }

    // MARK: - Project Header

    @ViewBuilder
    private var projectHeader: some View {
        HStack(spacing: 6) {
            chevronOrIndex

            if isRenaming {
                InlineRenameField(
                    text: Binding(
                        get: { appState.renameText },
                        set: { appState.renameText = $0 }
                    ),
                    font: .system(.body, weight: .medium),
                    onCancel: { appState.renamingProjectId = nil },
                    onCommit: { appState.commitProjectRename(project) }
                )
            } else {
                TruncatingText(project.name, font: configStore.primaryFont.weight(isActive ? .medium : .regular))
                    .foregroundStyle(isActive ? .primary : .secondary)
                Spacer()

                if !isExpanded && project.tabs.contains(where: { $0.needsAttention && !attention.isHidden($0.uuid) }) {
                    AttentionDot(needsAttention: true)
                        .padding(.trailing, 4)
                }
            }
        }
        .frame(minHeight: 28)
        .padding(.horizontal, 4)
        .background(
            RoundedRectangle(cornerRadius: 4)
                .fill(isHeaderHovered ? Color.primary.opacity(0.06) : Color.clear)
        )
        .contentShape(Rectangle())
        .onHover { isHeaderHovered = $0 }
        .onTapGesture { controller.selectProject(project) }
    }

    @ViewBuilder
    private var chevronOrIndex: some View {
        if modifiers.optionPressed && projectIndex >= 1 && projectIndex <= 9 {
            Text("\(projectIndex)")
                .font(.caption2)
                .fontWeight(.medium)
                .foregroundStyle(Color.accentColor)
                .frame(width: 16, height: 28)
                .contentShape(Rectangle())
                .onTapGesture {
                    withAnimation(.easeInOut(duration: 0.2)) { isExpanded.toggle() }
                }
        } else {
            Image(systemName: "chevron.right")
                .font(.caption2)
                .foregroundStyle(isChevronHovered ? .primary : .tertiary)
                .rotationEffect(.degrees(isExpanded ? 90 : 0))
                .frame(width: 16, height: 28)
                .contentShape(Rectangle())
                .onHover { isChevronHovered = $0 }
                .onTapGesture {
                    withAnimation(.easeInOut(duration: 0.2)) { isExpanded.toggle() }
                }
        }
    }

    // MARK: - Tab List

    @ViewBuilder
    private var tabList: some View {
        ReorderableStack(project.tabs, axis: .vertical, spacing: 0) { tab, isDragging in
            SidebarTabRow(
                tab: tab,
                isActive: isActive && tab.id == activeTabId,
                isHovered: hoveredTabId == tab.id,
                notificationsDisabled: attention.isHidden(tab.uuid),
                tabIndex: project.tabs.firstIndex(where: { $0.id == tab.id }).map { $0 + 1 } ?? 0
            )
            .contentShape(Rectangle())
            .onHover { hovering in hoveredTabId = hovering ? tab.id : nil }
            .onTapGesture {
                controller.selectProject(project)
                controller.selectTab(tab)
            }
            .contextMenu {
                Button("Rename") { appState.startTabRename(tab) }
                    .keyboardShortcut(KeyboardShortcuts.renameTab.key, modifiers: KeyboardShortcuts.renameTab.modifiers)
                if attention.isHidden(tab.uuid) {
                    Button("Enable Notifications") { attention.unhide(tab.uuid) }
                } else {
                    Button("Disable Notifications") { attention.hide(tab.uuid) }
                }
                Button("Close Tab", role: .destructive) { controller.removeTab(tab, in: project) }
                    .keyboardShortcut(KeyboardShortcuts.closePane.key, modifiers: KeyboardShortcuts.closePane.modifiers)
            }
        } onReorder: { from, to in
            controller.reorderTab(in: project, from: from, to: to)
        } onDragExit: { index, edge in
            guard let onTabDraggedOut, index < project.tabs.count else { return }
            onTabDraggedOut(project.tabs[index], edge)
        }
        .padding(.leading, 0)
        .transition(.opacity.combined(with: .move(edge: .top)))
    }
}
