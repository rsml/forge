import SwiftUI
import ForgeDomain

struct WindowTabBar: View {
    var session: Session
    var sidebarVisible: Bool = true
    var sidebarPosition: String = "left"
    var isFullScreen: Bool = false
    var onToggleSidebar: () -> Void = {}
    @Environment(WorkspaceController.self) var controller
    @State private var draggedTabId: String?
    @State private var renamingWindowId: String?
    @State private var renameText = ""

    private var tabBarOnBottom: Bool {
        let pos = ForgeConfigStore.shared.config.general?.tabBarPosition ??
                  ForgeConfigStore.shared.config.terminal?.tabBarPosition ??
                  ForgeConfigStore.shared.config.appearance?.tabBarPosition ?? "top"
        return pos == "bottom"
    }

    var body: some View {
        // Tab bar only (title bar is in SessionDetailView)
        HStack(spacing: 0) {
                // Show sidebar toggle when sidebar is hidden (left position)
                if !sidebarVisible && sidebarPosition != "right" {
                    IconButton(systemName: "sidebar.left") { onToggleSidebar() }
                        .frame(width: 40, height: 28)
                        .help(KeyboardShortcuts.toggleSidebar.tooltip)
                }

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 1) {
                        ForEach(Array(session.windows.enumerated()), id: \.element.id) { index, window in
                            if renamingWindowId == window.id {
                                InlineRenameField(text: $renameText, font: .system(.caption, weight: .regular), onCancel: { renamingWindowId = nil }) {
                                    if !renameText.isEmpty {
                                        controller.renameWindow(window, to: renameText)
                                    }
                                    renamingWindowId = nil
                                }
                                .fixedSize()
                                .frame(height: 28)
                            } else {
                                WindowTab(
                                    window: window,
                                    isActive: window.id == controller.workspace.activeWindowId,
                                    tabIndex: index + 1,
                                    indicatorOnTop: tabBarOnBottom
                                )
                                .opacity(draggedTabId == window.id ? 0.0 : 1.0)
                                .onDrag {
                                    draggedTabId = window.id
                                    return NSItemProvider(object: window.id as NSString)
                                }
                                .onDrop(of: [.text], delegate: ReorderDropDelegate(
                                    item: window,
                                    items: session.windows,
                                    draggedItemId: $draggedTabId,
                                    onMove: { from, to in
                                        session.windows.move(fromOffsets: from, toOffset: to)
                                    }
                                ))
                                .onTapGesture {
                                    controller.selectWindow(window)
                                }
                                .contextMenu {
                                    Button("Rename...") {
                                        renamingWindowId = window.id
                                        renameText = window.name
                                    }
                                    Divider()
                                    Button("Close Tab", role: .destructive) {
                                        controller.removeWindow(window, in: session)
                                    }
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 4)
                }
                .fixedSize(horizontal: true, vertical: false)

                Color.clear
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .contentShape(Rectangle())
                    .onTapGesture(count: 2) {
                        controller.addWindow(in: session)
                    }
                    .onDrop(of: [.text], isTargeted: nil) { providers in
                        guard let draggedId = draggedTabId,
                              let from = session.windows.firstIndex(where: { $0.id == draggedId })
                        else { return false }
                        let to = session.windows.count
                        if from != to - 1 {
                            withAnimation {
                                session.windows.move(fromOffsets: IndexSet(integer: from), toOffset: to)
                            }
                        }
                        draggedTabId = nil
                        return true
                    }
                    .contextMenu {
                        Button("New Tab") {
                            controller.addWindow(in: session)
                        }
                        Button("New Browser Tab") {}
                    }

                // Only show split icons in tab bar when tabs are on bottom OR fullscreen
                // (when tabs on top + windowed, they appear in the titlebar instead)
                if tabBarOnBottom || isFullScreen {
                    IconButton(systemName: "rectangle.split.2x1") {
                        controller.splitPane(direction: .horizontal)
                    }
                    .frame(width: 40, height: 28)
                    .help(KeyboardShortcuts.splitHorizontal.tooltip)

                    IconButton(systemName: "rectangle.split.1x2") {
                        controller.splitPane(direction: .vertical)
                    }
                    .frame(width: 40, height: 28)
                    .help(KeyboardShortcuts.splitVertical.tooltip)
                }

                // Show sidebar toggle when sidebar is hidden (right position)
                if !sidebarVisible && sidebarPosition == "right" {
                    IconButton(systemName: "sidebar.right") { onToggleSidebar() }
                        .frame(width: 40, height: 28)
                        .help(KeyboardShortcuts.toggleSidebar.tooltip)
                }
            }
        .frame(height: 28)
        .background(ForgeConfigStore.shared.resolvedTheme?.background ?? Color(nsColor: .controlBackgroundColor))
        .onReceive(NotificationCenter.default.publisher(for: .forgeRenameTab)) { _ in
            guard let windowId = controller.workspace.activeWindowId,
                  let window = session.windows.first(where: { $0.id == windowId }) else { return }
            renamingWindowId = window.id
            renameText = window.name
        }
    }
}


struct WindowTab: View {
    var window: ForgeDomain.Window
    let isActive: Bool
    var tabIndex: Int = 0
    var indicatorOnTop: Bool = false
    @State private var isHovered = false

    private var secondaryFont: Font {
        let config = ForgeConfigStore.shared.config.secondaryFont
        let family = config?.family ?? ".AppleSystemUIFont"
        let size = CGFloat(config?.size ?? 11)
        return .custom(family, size: size)
    }

    var body: some View {
        let modifiers = ModifierKeyMonitor.shared

        VStack(spacing: 0) {
            if indicatorOnTop {
                // Active tab indicator — flush to top
                RoundedRectangle(cornerRadius: 1)
                    .fill(isActive ? Color.accentColor.opacity(0.6) : Color.clear)
                    .frame(height: 2)
                    .padding(.horizontal, 6)
            }

            HStack(spacing: 4) {
                if modifiers.commandPressed && tabIndex >= 1 && tabIndex <= 9 {
                    Text("\(tabIndex)")
                        .font(.system(.caption, weight: .medium))
                        .foregroundStyle(Color.accentColor)
                        .frame(width: 14)
                }
                Text(window.name)
                    .font(secondaryFont)
                    .foregroundStyle((isActive || isHovered) ? .primary : .secondary)
                    .lineLimit(1)

                AttentionDot(needsAttention: window.needsAttention, size: 6)
            }
            .padding(.horizontal, 10)
            .frame(maxHeight: .infinity)
            .offset(y: indicatorOnTop ? -1 : 1)

            if !indicatorOnTop {
                // Active tab indicator — flush to bottom
                RoundedRectangle(cornerRadius: 1)
                    .fill(isActive ? Color.accentColor.opacity(0.6) : Color.clear)
                    .frame(height: 2)
                    .padding(.horizontal, 6)
            }
        }
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
    }
}
