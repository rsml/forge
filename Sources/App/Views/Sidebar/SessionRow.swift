import SwiftUI

struct SessionRow: View {
    var session: Session
    @Binding var isExpanded: Bool
    var onSelectWindow: (Window) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                // Chevron toggle
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isExpanded.toggle()
                    }
                } label: {
                    Image(systemName: "chevron.right")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                }
                .buttonStyle(.plain)
                .frame(width: 12, height: 12)

                // Attention indicator (blue if any child needs attention)
                AttentionDot(needsAttention: session.needsAttention, size: 8)

                Text(session.name)
                    .font(.system(.body, weight: .medium))
                    .lineLimit(1)

                Spacer()
            }

            if isExpanded {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(session.windows) { window in
                        WindowRow(window: window)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                onSelectWindow(window)
                            }
                    }
                }
                .padding(.leading, 24)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(.vertical, 2)
    }
}

struct WindowRow: View {
    var window: Window

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            HStack(spacing: 5) {
                Image(systemName: "terminal")
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                Text(window.name)
                    .font(.caption)
                    .lineLimit(1)

                if window.needsAttention {
                    AttentionDot(needsAttention: true, size: 5)
                }
            }
            .padding(.vertical, 2)

            ForEach(window.panes) { pane in
                PaneRow(pane: pane)
            }
        }
    }
}

struct PaneRow: View {
    var pane: Pane

    var body: some View {
        HStack(spacing: 5) {
            AttentionDot(needsAttention: pane.needsAttention, size: 5)

            Text(pane.currentCommand)
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .lineLimit(1)
        }
        .padding(.leading, 14)
    }
}
