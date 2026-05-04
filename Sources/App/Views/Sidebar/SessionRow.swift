import SwiftUI

struct SessionRow: View {
    var session: Session
    var isActive: Bool
    var activeWindowId: String?
    @Binding var isExpanded: Bool
    var isRenaming: Bool
    @Binding var renameText: String
    var onRenameCommit: () -> Void
    var onSelect: () -> Void
    var onSelectWindow: (Window) -> Void
    var renamingWindowId: String?
    var onStartWindowRename: (Window) -> Void = { _ in }
    var onRenameWindowCommit: () -> Void = {}

    @State private var isHeaderHovered = false
    @State private var isChevronHovered = false
    @State private var hoveredWindowId: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Project header — fixed height, vertically centered
            HStack(spacing: 6) {
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

                AttentionDot(needsAttention: session.needsAttention, size: 8)

                if isRenaming {
                    InlineRenameField(text: $renameText, font: .system(.body, weight: .medium), onCommit: onRenameCommit)
                } else {
                    Text(session.name)
                        .font(.system(.body, weight: isActive ? .medium : .regular))
                        .foregroundStyle(isActive ? .primary : .secondary)
                        .lineLimit(1)
                }

                Spacer()
            }
            .frame(height: 28)
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
                    ForEach(session.windows) { window in
                        SidebarTabRow(
                            window: window,
                            isActive: isActive && window.id == activeWindowId,
                            isHovered: hoveredWindowId == window.id,
                            isRenaming: renamingWindowId == window.id,
                            renameText: $renameText,
                            onRenameCommit: onRenameWindowCommit
                        )
                        .draggable(window.id)
                        .dropDestination(for: String.self) { droppedIds, _ in
                            guard let droppedId = droppedIds.first,
                                  let from = session.windows.firstIndex(where: { $0.id == droppedId }),
                                  let to = session.windows.firstIndex(where: { $0.id == window.id }),
                                  from != to
                            else { return false }
                            withAnimation(.easeInOut(duration: 0.2)) {
                                session.windows.move(fromOffsets: IndexSet(integer: from),
                                                     toOffset: to > from ? to + 1 : to)
                            }
                            return true
                        }
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
    var onCommit: () -> Void

    var body: some View {
        HStack(spacing: 4) {
            TextField("Name", text: $text, onCommit: onCommit)
                .textFieldStyle(.plain)
                .font(font)
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
    }
}

/// A tab row inside a project's expanded sidebar view.
struct SidebarTabRow: View {
    var window: Window
    var isActive: Bool
    var isHovered: Bool
    var isRenaming: Bool = false
    @Binding var renameText: String
    var onRenameCommit: () -> Void = {}

    var body: some View {
        HStack(spacing: 0) {
            // Subtle active indicator — thin left bar
            RoundedRectangle(cornerRadius: 1)
                .fill(isActive ? Color.accentColor.opacity(0.6) : Color.clear)
                .frame(width: 2, height: 12)
                .padding(.trailing, 4)

            if isRenaming {
                InlineRenameField(text: $renameText, font: .caption, onCommit: onRenameCommit)
            } else {
                Text(window.name)
                    .font(.caption)
                    .foregroundStyle(isActive ? .primary : .secondary)
                    .lineLimit(1)
            }

            if !isRenaming && window.needsAttention {
                AttentionDot(needsAttention: true, size: 5)
                    .padding(.leading, 4)
            }

            Spacer()
        }
        .padding(.horizontal, 4)
        .frame(height: 22)
        .background(
            RoundedRectangle(cornerRadius: 4)
                .fill(isHovered ? Color.primary.opacity(0.06) : Color.clear)
        )
    }
}
