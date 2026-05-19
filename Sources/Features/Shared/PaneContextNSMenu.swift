@preconcurrency import AppKit
import SwiftUI
import ForgeCore

/// AppKit-side mirror of `PaneContextMenu`. The terminal pane's underlying
/// NSView (GhosttyNSView) consumes right-click events to forward to the
/// ghostty surface, which prevents SwiftUI's `.contextMenu` modifier from
/// firing. Setting an `NSMenu` directly on the NSView (and popping it up in
/// the `rightMouseDown` override when present) restores the right-click menu
/// without breaking terminal-internal mouse behaviour.
///
/// The items here mirror `PaneContextMenu.body` 1:1 — both for a pane
/// surface (pane != nil) and a tab surface (pane == nil). Keep them in sync.
@MainActor
enum PaneContextNSMenu {
    /// Builds an NSMenu for a pane surface — same items as
    /// `PaneContextMenu(pane: pane)` in its SwiftUI form.
    static func make(
        controller: WorkspaceController,
        appState: AppState,
        attention: AttentionManager,
        project: Project,
        tab: ForgeCore.Tab,
        pane: Pane
    ) -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false

        // Splits
        menu.addItem(splitSubmenu(title: "Split right", direction: .horizontal, position: .after,
                                  controller: controller, pane: pane))
        menu.addItem(splitSubmenu(title: "Split down", direction: .vertical, position: .after,
                                  controller: controller, pane: pane))
        menu.addItem(splitSubmenu(title: "Split left", direction: .horizontal, position: .before,
                                  controller: controller, pane: pane))
        menu.addItem(splitSubmenu(title: "Split up", direction: .vertical, position: .before,
                                  controller: controller, pane: pane))

        menu.addItem(.separator())

        // New Tab / New Browser Tab
        menu.addItem(actionItem(
            "New Tab",
            shortcut: KeyboardShortcuts.newTab
        ) { [weak controller] in
            controller?.addTab(in: project)
        })
        menu.addItem(actionItem(
            "New Browser Tab",
            keyEquivalent: "t",
            modifiers: [.command, .option]
        ) { [weak controller] in
            controller?.addBrowserTab(in: project)
        })

        menu.addItem(.separator())

        // Rename Tab
        menu.addItem(actionItem(
            "Rename Tab",
            shortcut: KeyboardShortcuts.renameTab
        ) { [weak appState] in
            appState?.startTabRename(tab)
        })

        // Convert
        let convertTitle = pane.kind == .browser ? "Convert to Terminal" : "Convert to Browser"
        menu.addItem(actionItem(convertTitle) { [weak controller] in
            switch pane.kind {
            case .terminal: controller?.convertToBrowser(pane: pane)
            case .browser:  controller?.convertToTerminal(pane: pane)
            }
        })

        // Close
        let closeTitle = tab.panes.count > 1 ? "Close Pane" : "Close Tab"
        let closeItem = actionItem(
            closeTitle,
            shortcut: KeyboardShortcuts.closePane
        ) { [weak controller] in
            guard let controller else { return }
            if tab.panes.count > 1 {
                controller.closePane(pane.id)
            } else {
                controller.removeTab(tab, in: project)
            }
        }
        menu.addItem(closeItem)

        menu.addItem(.separator())

        // Notifications toggle
        let isHidden = attention.isHidden(tab.uuid)
        let notifyTitle = isHidden ? "Enable Notifications" : "Disable Notifications"
        menu.addItem(actionItem(
            notifyTitle,
            shortcut: KeyboardShortcuts.toggleNotifications
        ) { [weak attention] in
            if isHidden { attention?.unhide(tab.uuid) }
            else        { attention?.hide(tab.uuid) }
        })

        return menu
    }

    // MARK: - Builders

    private static func splitSubmenu(
        title: String,
        direction: SplitDirection,
        position: SplitPosition,
        controller: WorkspaceController,
        pane: Pane
    ) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        let submenu = NSMenu(title: title)
        submenu.autoenablesItems = false
        submenu.addItem(actionItem("As Terminal") { [weak controller] in
            controller?.lastFocusedPaneId = pane.id
            controller?.splitPane(direction: direction, position: position, as: .terminal)
        })
        submenu.addItem(actionItem("As Browser") { [weak controller] in
            controller?.lastFocusedPaneId = pane.id
            controller?.splitPane(direction: direction, position: position, as: .browser)
        })
        item.submenu = submenu
        return item
    }

    /// Action item using the same key/modifiers as a registered `Shortcut`.
    private static func actionItem(
        _ title: String,
        shortcut: Shortcut,
        action: @escaping @MainActor () -> Void
    ) -> NSMenuItem {
        actionItem(
            title,
            keyEquivalent: keyEquivalentString(for: shortcut.key),
            modifiers: nsModifiers(for: shortcut.modifiers),
            action: action
        )
    }

    /// Action item with no keyboard equivalent.
    private static func actionItem(
        _ title: String,
        action: @escaping @MainActor () -> Void
    ) -> NSMenuItem {
        actionItem(title, keyEquivalent: "", modifiers: [], action: action)
    }

    /// Action item with explicit key equivalent.
    private static func actionItem(
        _ title: String,
        keyEquivalent: String,
        modifiers: NSEvent.ModifierFlags,
        action: @escaping @MainActor () -> Void
    ) -> NSMenuItem {
        let item = NSMenuItem(
            title: title,
            action: #selector(BlockMenuTarget.fire(_:)),
            keyEquivalent: keyEquivalent
        )
        item.keyEquivalentModifierMask = modifiers
        item.isEnabled = true
        let target = BlockMenuTarget(block: action)
        item.target = target
        // Retain the BlockMenuTarget for the lifetime of the menu item.
        item.representedObject = target
        return item
    }

    /// Map a SwiftUI `KeyEquivalent` to its AppKit string representation.
    /// Only handles the characters we actually use in `PaneContextMenu`.
    private static func keyEquivalentString(for key: KeyEquivalent) -> String {
        switch key {
        case .return:     return "\r"
        case .tab:        return "\t"
        case .delete:     return String(Character(UnicodeScalar(NSBackspaceCharacter)!))
        case .escape:     return String(Character(UnicodeScalar(0x1B)!))
        case .upArrow:    return String(Character(UnicodeScalar(NSUpArrowFunctionKey)!))
        case .downArrow:  return String(Character(UnicodeScalar(NSDownArrowFunctionKey)!))
        case .leftArrow:  return String(Character(UnicodeScalar(NSLeftArrowFunctionKey)!))
        case .rightArrow: return String(Character(UnicodeScalar(NSRightArrowFunctionKey)!))
        case .space:      return " "
        default:          return String(key.character)
        }
    }

    /// Convert SwiftUI `EventModifiers` to `NSEvent.ModifierFlags`.
    private static func nsModifiers(for mods: EventModifiers) -> NSEvent.ModifierFlags {
        var flags: NSEvent.ModifierFlags = []
        if mods.contains(.command) { flags.insert(.command) }
        if mods.contains(.shift)   { flags.insert(.shift) }
        if mods.contains(.option)  { flags.insert(.option) }
        if mods.contains(.control) { flags.insert(.control) }
        return flags
    }
}

// MARK: - BlockMenuTarget

/// Bridges an NSMenuItem `action:` selector to a Swift closure. The item retains
/// this target through `representedObject` so the closure stays alive for the
/// life of the menu.
@MainActor
final class BlockMenuTarget: NSObject {
    private let block: @MainActor () -> Void
    init(block: @escaping @MainActor () -> Void) {
        self.block = block
        super.init()
    }
    @objc func fire(_ sender: Any?) { block() }
}
