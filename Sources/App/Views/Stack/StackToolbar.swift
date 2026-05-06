import SwiftUI
import ForgeDomain

struct StackToolbar: View {
    let session: Session
    let window: ForgeDomain.Window
    @Environment(AttentionManager.self) var attention

    var body: some View {
        HStack(spacing: 0) {
            labels
                .padding(.leading, 4)
            Spacer()
            actionButtons
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 2)
        .background {
            if let theme = ForgeConfigStore.shared.resolvedTheme {
                theme.background
                Color.white.opacity(0.06)
            } else {
                Color(nsColor: .windowBackgroundColor)
            }
        }
    }

    private var labels: some View {
        HStack(spacing: 6) {
            Text(session.name)
                .font(.system(size: 12, weight: .medium))
            Text(window.name)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
        }
    }

    private var actionButtons: some View {
        HStack(spacing: 0) {
            IconButton(systemName: "checkmark") {
                for pane in window.panes {
                    pane.hasBell = false
                    pane.hasContentMatch = false
                }
                attention.markDone(window.uuid)
            }
            .frame(width: 40, height: 28)
            .help(KeyboardShortcuts.stackDone.tooltip)

            IconButton(systemName: "bell.slash") {
                attention.hide(window.uuid)
            }
            .frame(width: 40, height: 28)
            .help("Disable Notifications")

            IconButton(systemName: "arrow.right.to.line") {
                attention.moveToBack(window.uuid)
            }
            .frame(width: 40, height: 28)
            .help(KeyboardShortcuts.stackMoveToBack.tooltip)
        }
    }
}
