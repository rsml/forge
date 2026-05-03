import SwiftUI

struct SessionRow: View {
    var session: Session
    @Binding var isExpanded: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
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
                .frame(width: 16, height: 16)

                StatusDot(status: session.aggregateStatus)

                Text(session.name)
                    .font(.system(.body, weight: .medium))
                    .lineLimit(1)

                Spacer()

                if session.windowCount > 1 {
                    Text("\(session.windowCount)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if isExpanded {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(session.windows) { window in
                        WindowRow(window: window)
                    }
                }
                .padding(.leading, 28)
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
            HStack(spacing: 6) {
                Image(systemName: "rectangle.split.3x1")
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                Text(window.name)
                    .font(.caption)
                    .lineLimit(1)

                if window.active {
                    Circle()
                        .fill(.blue)
                        .frame(width: 4, height: 4)
                }
            }

            ForEach(window.panes) { pane in
                PaneRow(pane: pane)
            }
        }
    }
}

struct PaneRow: View {
    var pane: Pane

    var body: some View {
        HStack(spacing: 6) {
            StatusDot(status: pane.status, size: 6)

            Text(pane.currentCommand)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(.leading, 16)
    }
}
