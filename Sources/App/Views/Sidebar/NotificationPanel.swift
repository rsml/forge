import SwiftUI
import ForgeDomain

struct NotificationPanel: View {
    var onDismiss: (() -> Void)? = nil
    @Environment(WorkspaceController.self) var controller
    @Environment(AttentionManager.self) var attention
    @Environment(\.dismiss) var dismiss

    private var attentionItems: [(session: Session, window: ForgeDomain.Window)] {
        controller.workspace.sessions.flatMap { session in
            session.windows
                .filter { $0.needsAttention && !attention.isHidden($0.uuid) }
                .map { (session: session, window: $0) }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Notifications")
                    .font(.headline)
                Spacer()
                if !attentionItems.isEmpty {
                    Button("Clear All") { clearAll() }
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                        .font(.caption)
                }
            }
            .padding(16)

            Divider()

            if attentionItems.isEmpty {
                VStack {
                    Spacer()
                    Text("No notifications")
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .frame(minHeight: 150)
                .padding(.vertical, 16)
            } else {
                List {
                    ForEach(attentionItems, id: \.window.id) { item in
                        Button {
                            controller.selectSession(item.session)
                            // Navigate to the window that needs attention
                            controller.selectWindow(item.window)
                            close()
                        } label: {
                            HStack {
                                AttentionDot(needsAttention: true, size: 6)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(item.session.name)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    Text(item.window.name)
                                        .font(.body)
                                }
                                Spacer()
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .listStyle(.plain)
            }

            Divider()

            HStack {
                if let latest = attentionItems.first {
                    Button("Jump to Latest") {
                        controller.selectSession(latest.session)
                        // selectWindow automatically clears hasBell for this window's panes
                        controller.selectWindow(latest.window)
                        close()
                    }
                }
                Spacer()
                Button("Done") { close() }
                    .keyboardShortcut(.cancelAction)
            }
            .padding(16)
        }
    }

    private func close() {
        if let onDismiss { onDismiss() } else { dismiss() }
    }

    private func clearAll() {
        for session in controller.workspace.sessions {
            for window in session.windows {
                for pane in window.panes {
                    pane.hasBell = false
                    pane.hasContentMatch = false
                }
            }
        }
    }
}
