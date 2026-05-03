import SwiftUI

struct WindowTabBar: View {
    var session: Session
    @Environment(WorkspaceController.self) var controller

    var body: some View {
        HStack(spacing: 0) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 1) {
                    ForEach(session.windows) { window in
                        WindowTab(
                            window: window,
                            isActive: window.id == controller.workspace.activeWindowId
                        )
                        .onTapGesture {
                            controller.selectWindow(window)
                        }
                        .contextMenu {
                            Button("Rename...") {}
                            Divider()
                            Button("Close Window", role: .destructive) {
                                controller.removeWindow(window)
                            }
                        }
                    }
                }
                .padding(.horizontal, 4)
            }

            Spacer()

            Button {
                controller.addWindow(in: session)
            } label: {
                Image(systemName: "plus")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 8)
        }
        .frame(height: 32)
        .background(Color(nsColor: .controlBackgroundColor))
    }
}

struct WindowTab: View {
    var window: Window
    let isActive: Bool

    var body: some View {
        HStack(spacing: 4) {
            Text("\(window.index): \(window.name)")
                .font(.system(.caption, weight: isActive ? .semibold : .regular))
                .lineLimit(1)

            // Blue dot if any pane in this window needs attention
            AttentionDot(needsAttention: window.needsAttention, size: 6)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(isActive ? Color.accentColor.opacity(0.15) : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 4))
    }
}
