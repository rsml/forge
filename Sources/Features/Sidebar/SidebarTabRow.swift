import SwiftUI
import ForgeCore

/// A tab row inside a project's expanded sidebar view.
struct SidebarTabRow: View {
    @Environment(ForgeConfigStore.self) private var configStore
    @Environment(AppState.self) private var appState
    @Environment(ModifierKeyMonitor.self) private var modifiers
    var tab: ForgeCore.Tab
    var isActive: Bool
    var isHovered: Bool
    var notificationsDisabled: Bool = false
    var tabIndex: Int = 0

    var body: some View {
        let isRenaming = appState.renamingTabId == tab.id

        HStack(spacing: 0) {
            // Cmd held: show tab number instead of active indicator
            if modifiers.commandPressed && tabIndex >= 1 && tabIndex <= 9 {
                Text("\(tabIndex)")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 14, height: 12)
                    .padding(.trailing, 2)
            } else {
                // Subtle active indicator — thin left bar
                RoundedRectangle(cornerRadius: 1)
                    .fill(isActive ? Color.accentColor.opacity(0.6) : Color.clear)
                    .frame(width: 2, height: 12)
                    .padding(.trailing, 4)
            }

            if isRenaming {
                InlineRenameField(
                    text: Binding(
                        get: { appState.renameText },
                        set: { appState.renameText = $0 }
                    ),
                    font: .caption,
                    onCancel: { appState.renamingTabId = nil },
                    onCommit: { appState.commitTabRename(tab) }
                )
            } else {
                TruncatingText(tab.name, font: configStore.secondaryFont)
                    .foregroundStyle(isActive ? .primary : .secondary)

                Spacer()

                if tab.needsAttention && !notificationsDisabled {
                    AttentionDot(needsAttention: true, size: 6)
                        .padding(.trailing, 4)
                }
            }
        }
        .padding(.horizontal, 4)
        .frame(height: 22)
        .background(
            RoundedRectangle(cornerRadius: 4)
                .fill(isHovered ? Color.primary.opacity(0.06) : Color.clear)
        )
    }
}
