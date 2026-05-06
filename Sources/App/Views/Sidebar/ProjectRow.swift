import SwiftUI
import ForgeDomain

struct SidebarProjectRow: View {
    var project: Project
    var isActive: Bool

    var activeTabId: String?
    @Binding var isExpanded: Bool
    var isRenaming: Bool
    @Binding var renameText: String
    var onRenameCommit: () -> Void
    var onRenameCancel: () -> Void = {}
    var renamingTabId: String?
    var onStartTabRename: (ForgeDomain.Tab) -> Void = { _ in }
    var onRenameTabCommit: () -> Void = {}
    var onRenameTabCancel: () -> Void = {}
    var onTabDraggedOut: ((ForgeDomain.Tab, Edge) -> Void)?
    var projectIndex: Int = 0

    @Environment(WorkspaceController.self) var controller
    @Environment(AttentionManager.self) var attention
    @State private var isHeaderHovered = false
    @State private var isChevronHovered = false
    @State private var hoveredTabId: String?

    var body: some View {
        let modifiers = ModifierKeyMonitor.shared

        VStack(alignment: .leading, spacing: 0) {
            // Project header — fixed height, vertically centered
            HStack(spacing: 6) {
                if modifiers.optionPressed && projectIndex >= 1 && projectIndex <= 9 {
                    Text("\(projectIndex)")
                        .font(.caption2)
                        .fontWeight(.medium)
                        .foregroundStyle(Color.accentColor)
                        .frame(width: 16, height: 28)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                isExpanded.toggle()
                            }
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
                            withAnimation(.easeInOut(duration: 0.2)) {
                                isExpanded.toggle()
                            }
                        }
                }

                if isRenaming {
                    InlineRenameField(text: $renameText, font: .system(.body, weight: .medium), onCancel: onRenameCancel, onCommit: onRenameCommit)
                } else {
                    TruncatingText(project.name, font: ForgeConfigStore.shared.primaryFont.weight(isActive ? .medium : .regular))
                        .foregroundStyle(isActive ? .primary : .secondary)
                    Spacer()

                    if !isExpanded && project.tabs.contains(where: { $0.needsAttention && !attention.isHidden($0.uuid) }) {
                        AttentionDot(needsAttention: true, size: 9)
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
            .onHover { hovering in
                isHeaderHovered = hovering
            }
            .onTapGesture {
                controller.selectProject(project)
            }

            // Expanded tab list
            if isExpanded {
                ReorderableStack(project.tabs, axis: .vertical, spacing: 0) { tab, isDragging in
                    SidebarTabRow(
                        tab: tab,
                        isActive: isActive && tab.id == activeTabId,
                        isHovered: hoveredTabId == tab.id,
                        isRenaming: renamingTabId == tab.id,
                        notificationsDisabled: attention.isHidden(tab.uuid),
                        tabIndex: project.tabs.firstIndex(where: { $0.id == tab.id }).map { $0 + 1 } ?? 0,
                        renameText: $renameText,
                        onRenameCommit: onRenameTabCommit,
                        onRenameCancel: onRenameTabCancel
                    )
                    .contentShape(Rectangle())
                    .onHover { hovering in
                        hoveredTabId = hovering ? tab.id : nil
                    }
                    .onTapGesture {
                        controller.selectProject(project)
                        controller.selectTab(tab)
                    }
                    .contextMenu {
                        Button("Rename") { onStartTabRename(tab) }
                            .keyboardShortcut(KeyboardShortcuts.renameTab.key, modifiers: KeyboardShortcuts.renameTab.modifiers)
                        if attention.isHidden(tab.uuid) {
                            Button("Enable Notifications") {
                                attention.unhide(tab.uuid)
                            }
                        } else {
                            Button("Disable Notifications") {
                                attention.hide(tab.uuid)
                            }
                        }
                        Button("Close Tab", role: .destructive) {
                            controller.removeTab(tab, in: project)
                        }
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
    }
}

/// Inline text field with a checkmark commit button.
struct InlineRenameField: View {
    @Binding var text: String
    var font: Font = .caption
    var onCancel: () -> Void = {}
    var onCommit: () -> Void
    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: 2) {
            TextField("Name", text: $text, onCommit: onCommit)
                .textFieldStyle(.plain)
                .font(font)
                .focused($isFocused)
                .padding(.horizontal, 4)
                .padding(.vertical, 2)
                .background(
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.primary.opacity(0.06))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 3)
                        .strokeBorder(Color.accentColor.opacity(0.4), lineWidth: 1)
                )

            IconButton(systemName: "checkmark", font: .system(size: 10, weight: .semibold)) {
                onCommit()
            }
            .frame(width: 20, height: 20)
        }
        .onKeyPress(.escape) { onCancel(); return .handled }
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                isFocused = true
            }
        }
    }
}

/// A tab row inside a project's expanded sidebar view.
struct SidebarTabRow: View {
    var tab: ForgeDomain.Tab
    var isActive: Bool
    var isHovered: Bool
    var isRenaming: Bool = false
    var notificationsDisabled: Bool = false
    var tabIndex: Int = 0
    @Binding var renameText: String
    var onRenameCommit: () -> Void = {}
    var onRenameCancel: () -> Void = {}

    var body: some View {
        let modifiers = ModifierKeyMonitor.shared

        HStack(spacing: 0) {
            // Cmd held: show tab number instead of active indicator
            if modifiers.commandPressed && tabIndex >= 1 && tabIndex <= 9 {
                Text("\(tabIndex)")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 14, height: 12)
                    .padding(.trailing, 2)
            } else {
                // Subtle active indicator — thin left bar
                RoundedRectangle(cornerRadius: 1)
                    .fill(isActive ? Color.accentColor.opacity(0.6) : Color.clear)
                    .frame(width: 2, height: 12)
                    .padding(.trailing, 4)
            }

            if isRenaming {
                InlineRenameField(text: $renameText, font: .caption, onCancel: onRenameCancel, onCommit: onRenameCommit)
            } else {
                TruncatingText(tab.name, font: ForgeConfigStore.shared.secondaryFont)
                    .foregroundStyle(isActive ? .primary : .secondary)

                Spacer()

                if tab.needsAttention && !notificationsDisabled {
                    AttentionDot(needsAttention: true, size: 6)
                        .padding(.trailing, 4)
                }
            }
        }
        .padding(.horizontal, 4)
        .frame(height: 22)
        .background(
            RoundedRectangle(cornerRadius: 4)
                .fill(isHovered ? Color.primary.opacity(0.06) : Color.clear)
        )
    }
}
