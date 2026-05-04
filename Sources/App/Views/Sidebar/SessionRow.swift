import SwiftUI

struct SessionRow: View {
    var session: Session
    var isActive: Bool
    var activeWindowId: String?
    @Binding var isExpanded: Bool
    var isRenaming: Bool
    @Binding var renameText: String
    var onRenameCommit: () -> Void
    var onRenameCancel: () -> Void = {}
    var onSelect: () -> Void
    var onSelectWindow: (Window) -> Void
    var renamingWindowId: String?
    var onStartWindowRename: (Window) -> Void = { _ in }
    var onRenameWindowCommit: () -> Void = {}
    var onRenameWindowCancel: () -> Void = {}
    var projectIndex: Int = 0

    @State private var isHeaderHovered = false
    @State private var isChevronHovered = false
    @State private var hoveredWindowId: String?
    @State private var draggedWindowId: String?

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

                AttentionDot(needsAttention: session.needsAttention, size: 8)

                if isRenaming {
                    InlineRenameField(text: $renameText, font: .system(.body, weight: .medium), onCancel: onRenameCancel, onCommit: onRenameCommit)
                } else {
                    Text(session.name)
                        .font(.system(.body, weight: isActive ? .medium : .regular))
                        .foregroundStyle(isActive ? .primary : .secondary)
                        .lineLimit(1)
                    Spacer()
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
                onSelect()
            }

            // Expanded window list
            if isExpanded {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(session.windows.enumerated()), id: \.element.id) { index, window in
                        SidebarTabRow(
                            window: window,
                            isActive: isActive && window.id == activeWindowId,
                            isHovered: hoveredWindowId == window.id,
                            isRenaming: renamingWindowId == window.id,
                            tabIndex: index + 1,
                            renameText: $renameText,
                            onRenameCommit: onRenameWindowCommit,
                            onRenameCancel: onRenameWindowCancel
                        )
                        .opacity(draggedWindowId == window.id ? 0.0 : 1.0)
                        .onDrag {
                            draggedWindowId = window.id
                            return NSItemProvider(object: window.id as NSString)
                        }
                        .onDrop(of: [.text], delegate: ReorderDropDelegate(
                            item: window,
                            items: session.windows,
                            draggedItemId: $draggedWindowId,
                            onMove: { from, to in
                                session.windows.move(fromOffsets: from, toOffset: to)
                            }
                        ))
                        .contentShape(Rectangle())
                        .onHover { hovering in
                            hoveredWindowId = hovering ? window.id : nil
                        }
                        .onTapGesture {
                            onSelectWindow(window)
                        }
                        .contextMenu {
                            Button("Rename...") { onStartWindowRename(window) }
                            Divider()
                            Button("Close Tab", role: .destructive) {
                                onSelectWindow(window)
                            }
                        }
                    }
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
    var window: Window
    var isActive: Bool
    var isHovered: Bool
    var isRenaming: Bool = false
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
                Text(window.name)
                    .font(.caption)
                    .foregroundStyle(isActive ? .primary : .secondary)
                    .lineLimit(1)

                if window.needsAttention {
                    AttentionDot(needsAttention: true, size: 5)
                        .padding(.leading, 4)
                }

                Spacer()
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
