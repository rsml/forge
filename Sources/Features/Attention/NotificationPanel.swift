import SwiftUI
import ForgeCore

struct NotificationPanel: View {
    var onDismiss: (() -> Void)? = nil
    @Environment(WorkspaceController.self) var controller
    @Environment(AttentionManager.self) var attention
    @Environment(\.dismiss) var dismiss

    private var attentionItems: [(project: Project, tab: ForgeCore.Tab)] {
        controller.workspace.projects.flatMap { project in
            project.tabs
                .filter { $0.needsAttention && !attention.isHidden($0.uuid) }
                .map { (project: project, tab: $0) }
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
                    ForEach(attentionItems, id: \.tab.id) { item in
                        Button {
                            controller.navigateToTab(item.tab, in: item.project)
                            close()
                            DispatchQueue.main.async {
                                NotificationCenter.default.post(name: .forgeFocusTerminal, object: nil)
                            }
                        } label: {
                            HStack {
                                AttentionDot(needsAttention: true)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(item.project.name)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    Text(item.tab.name)
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
                        controller.navigateToTab(latest.tab, in: latest.project)
                        close()
                        DispatchQueue.main.async {
                            NotificationCenter.default.post(name: .forgeFocusTerminal, object: nil)
                        }
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
        for project in controller.workspace.projects {
            for tab in project.tabs {
                for pane in tab.panes {
                    pane.hasBell = false
                    pane.hasContentMatch = false
                }
                Task { await controller.tmux.clearBellFlag(tabId: tab.id) }
            }
        }
    }
}
