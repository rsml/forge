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
    var onMoveWindow: (IndexSet, Int) -> Void

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
                    TextField("Project name", text: $renameText, onCommit: onRenameCommit)
                        .textFieldStyle(.plain)
                        .font(.system(.body, weight: .medium))
                } else {
                    Text(session.name)
                        .font(.system(.body, weight: .medium))
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
                            isHovered: hoveredWindowId == window.id
                        )
                        .contentShape(Rectangle())
                        .onHover { hovering in
                            hoveredWindowId = hovering ? window.id : nil
                        }
                        .onTapGesture {
                            onSelectWindow(window)
                        }
                    }
                    .onMove(perform: onMoveWindow)
                }
                .padding(.leading, 10)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }
}

/// A tab row inside a project's expanded sidebar view.
struct SidebarTabRow: View {
    var window: Window
    var isActive: Bool
    var isHovered: Bool

    var body: some View {
        HStack(spacing: 0) {
            // Subtle active indicator — thin left bar
            RoundedRectangle(cornerRadius: 1)
                .fill(isActive ? Color.accentColor.opacity(0.6) : Color.clear)
                .frame(width: 2, height: 12)
                .padding(.trailing, 4)

            Text(displayName)
                .font(.caption)
                .foregroundStyle(isActive ? .primary : .secondary)
                .lineLimit(1)

            if window.needsAttention {
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

    private var displayName: String {
        guard let pane = window.panes.first,
              !pane.currentCommand.isEmpty,
              pane.currentCommand != window.name else {
            return window.name
        }
        return "\(window.name) — \(pane.currentCommand)"
    }
}
