import SwiftUI
import ForgeCore

struct StackToolbar: View {
    @Environment(ForgeConfigStore.self) private var configStore
    let project: Project
    let tab: ForgeCore.Tab
    var onDismiss: ((WorkspaceController.StackDismissAction) -> Void)?
    var onSplit: ((SplitDirection) -> Void)?
    var onNewTab: (() -> Void)?

    var body: some View {
        HStack(spacing: 0) {
            leftGroup
                .padding(.leading, 4)
            Spacer()
            rightGroup
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 2)
        .background {
            if let theme = configStore.resolvedTheme {
                theme.background.color
                Color.white.opacity(0.06)
            } else {
                Color(nsColor: .windowBackgroundColor)
            }
        }
    }

    private var leftGroup: some View {
        HStack(spacing: 6) {
            if onNewTab != nil {
                IconButton(systemName: "plus") {
                    onNewTab?()
                }
                .frame(width: 40, height: 28)
                .tooltip(KeyboardShortcuts.newTab)
            }
            Text(project.name)
                .font(.system(size: 12, weight: .medium))
            Text(tab.name)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
        }
    }

    private var rightGroup: some View {
        HStack(spacing: 0) {
            splitButtons
            dismissButtons
        }
    }

    private var splitButtons: some View {
        HStack(spacing: 0) {
            IconButton(systemName: "rectangle.split.2x1") {
                onSplit?(.horizontal)
            }
            .frame(width: 40, height: 28)
            .tooltip(KeyboardShortcuts.splitHorizontal)

            IconButton(systemName: "rectangle.split.1x2") {
                onSplit?(.vertical)
            }
            .frame(width: 40, height: 28)
            .tooltip(KeyboardShortcuts.splitVertical)
        }
        .opacity(onSplit == nil ? 0.5 : 1.0)
        .allowsHitTesting(onSplit != nil)
    }

    private var dismissButtons: some View {
        HStack(spacing: 0) {
            IconButton(systemName: "checkmark") {
                onDismiss?(.done)
            }
            .frame(width: 40, height: 28)
            .tooltip(KeyboardShortcuts.stackDone)

            IconButton(systemName: "bell.slash") {
                onDismiss?(.hide)
            }
            .frame(width: 40, height: 28)
            .tooltip("Disable Notifications", shortcut: KeyboardShortcuts.stackHide)

            IconButton(systemName: "arrow.right.to.line") {
                onDismiss?(.moveToBack)
            }
            .frame(width: 40, height: 28)
            .tooltip(KeyboardShortcuts.stackMoveToBack)
        }
        .opacity(onDismiss == nil ? 0.5 : 1.0)
        .allowsHitTesting(onDismiss != nil)
    }
}
