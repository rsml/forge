import SwiftUI

struct NotificationPanel: View {
    @Environment(WorkspaceController.self) var controller
    @Environment(\.dismiss) var dismiss

    private var attentionItems: [(session: Session, window: Window)] {
        controller.workspace.sessions.flatMap { session in
            session.windows.filter { $0.needsAttention }.map { (session: session, window: $0) }
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
            } else {
                List {
                    ForEach(attentionItems, id: \.window.id) { item in
                        Button {
                            controller.selectSession(item.session)
                            controller.selectWindow(item.window)
                            dismiss()
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
                        controller.selectWindow(latest.window)
                        dismiss()
                    }
                }
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
            .padding(16)
        }
        .frame(width: 350, height: 400)
    }

    private func clearAll() {
        for session in controller.workspace.sessions {
            for window in session.windows {
                for pane in window.panes {
                    pane.hasBell = false
                }
            }
        }
    }
}
