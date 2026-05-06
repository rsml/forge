import SwiftUI
import ForgeDomain

struct StackToolbar: View {
    let session: Session
    let window: ForgeDomain.Window
    @Environment(AttentionManager.self) var attention

    private var sidebarPosition: String {
        ForgeConfigStore.shared.config.general?.sidebarPosition ?? "left"
    }

    var body: some View {
        HStack(spacing: 12) {
            if sidebarPosition == "left" {
                actionButtons
                Spacer()
                labels
            } else {
                labels
                Spacer()
                actionButtons
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background {
            if let theme = ForgeConfigStore.shared.resolvedTheme {
                theme.background
                Color.white.opacity(0.06)
            } else {
                Color(nsColor: .windowBackgroundColor)
            }
        }
    }

    @ViewBuilder
    private var labels: some View {
        if sidebarPosition == "left" {
            Text(session.name)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
            Text(window.name)
                .font(.system(size: 12, weight: .medium))
        } else {
            Text(session.name)
                .font(.system(size: 12, weight: .medium))
            Text(window.name)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var actionButtons: some View {
        HStack(spacing: 8) {
            Button {
                for pane in window.panes { pane.hasBell = false }
                attention.markDone(window.uuid)
            } label: {
                Image(systemName: "checkmark")
            }
            .help("Done")

            Button { attention.hide(window.uuid) } label: {
                Image(systemName: "eye.slash")
            }
            .help("Hide")

            Button { attention.moveToBack(window.uuid) } label: {
                Image(systemName: "arrow.right.to.line")
            }
            .help("Move to Back")
        }
        .buttonStyle(.borderless)
    }
}
