import SwiftUI
import ForgeDomain

/// Default keyboard shortcuts for all Forge actions.
/// Overrides are resolved from ForgeConfigStore at access time.
@MainActor
enum KeyboardShortcuts {
    // MARK: - File
    static var newProject: Shortcut { resolve("newProject", default: Shortcut("n", modifiers: .command, label: "New Project")) }
    static var newTab: Shortcut { resolve("newTab", default: Shortcut("t", modifiers: .command, label: "New Tab")) }
    static var closePane: Shortcut { resolve("closePane", default: Shortcut("w", modifiers: .command, label: "Close Pane")) }
    static var closeProject: Shortcut { resolve("closeProject", default: Shortcut("w", modifiers: [.command, .shift], label: "Close Project")) }
    static var renameTab: Shortcut { resolve("renameTab", default: Shortcut("t", modifiers: [.command, .shift], label: "Rename Tab")) }
    static var renameProject: Shortcut { resolve("renameProject", default: Shortcut("p", modifiers: [.command, .shift], label: "Rename Project")) }

    // MARK: - View
    static var toggleSidebar: Shortcut { resolve("toggleSidebar", default: Shortcut("b", modifiers: .command, label: "Toggle Sidebar")) }
    static var commandPalette: Shortcut { resolve("commandPalette", default: Shortcut("p", modifiers: .command, label: "Command Palette")) }
    static var notifications: Shortcut { resolve("notifications", default: Shortcut("n", modifiers: [.command, .shift], label: "Notifications")) }
    static var toggleMode: Shortcut { resolve("toggleMode", default: Shortcut("m", modifiers: [.command, .shift], label: "Toggle Mode")) }

    // MARK: - Stack
    static var stackDone: Shortcut { resolve("stackDone", default: Shortcut(.return, modifiers: .command, label: "Done")) }
    static var stackHide: Shortcut { resolve("stackHide", default: Shortcut("h", modifiers: [.command, .shift], label: "Hide")) }
    static var stackMoveToBack: Shortcut { resolve("stackMoveToBack", default: Shortcut("]", modifiers: [.command, .shift], label: "Move to Back")) }

    // MARK: - Splits
    static var splitHorizontal: Shortcut { resolve("splitHorizontal", default: Shortcut("d", modifiers: .command, label: "Split Horizontally")) }
    static var splitVertical: Shortcut { resolve("splitVertical", default: Shortcut("d", modifiers: [.command, .shift], label: "Split Vertically")) }

    // MARK: - Tabs
    static var selectTabLeft: Shortcut { resolve("selectTabLeft", default: Shortcut("[", modifiers: [.command, .shift], label: "Select Tab Left")) }
    static var selectTabRight: Shortcut { resolve("selectTabRight", default: Shortcut("]", modifiers: [.command, .shift], label: "Select Tab Right")) }
    static var moveTabLeft: Shortcut { resolve("moveTabLeft", default: Shortcut(.leftArrow, modifiers: [.command, .shift], label: "Move Tab Left")) }
    static var moveTabRight: Shortcut { resolve("moveTabRight", default: Shortcut(.rightArrow, modifiers: [.command, .shift], label: "Move Tab Right")) }

    // MARK: - Projects
    static var nextProject: Shortcut { resolve("nextProject", default: Shortcut(.tab, modifiers: .control, label: "Next Project")) }
    static var prevProject: Shortcut { resolve("prevProject", default: Shortcut(.tab, modifiers: [.control, .shift], label: "Previous Project")) }

    // MARK: - App
    static var settings: Shortcut { resolve("settings", default: Shortcut(",", modifiers: .command, label: "Settings")) }
    static var clearScrollback: Shortcut { resolve("clearScrollback", default: Shortcut("k", modifiers: .command, label: "Clear Scrollback")) }

    // MARK: - All Defaults (for settings UI)
    static let allDefaults: [(id: String, shortcut: Shortcut, category: String)] = [
        ("newProject", Shortcut("n", modifiers: .command, label: "New Project"), "File"),
        ("newTab", Shortcut("t", modifiers: .command, label: "New Tab"), "File"),
        ("closePane", Shortcut("w", modifiers: .command, label: "Close Pane"), "File"),
        ("closeProject", Shortcut("w", modifiers: [.command, .shift], label: "Close Project"), "File"),
        ("renameTab", Shortcut("t", modifiers: [.command, .shift], label: "Rename Tab"), "File"),
        ("renameProject", Shortcut("p", modifiers: [.command, .shift], label: "Rename Project"), "File"),
        ("toggleSidebar", Shortcut("b", modifiers: .command, label: "Toggle Sidebar"), "View"),
        ("commandPalette", Shortcut("p", modifiers: .command, label: "Command Palette"), "View"),
        ("notifications", Shortcut("n", modifiers: [.command, .shift], label: "Notifications"), "View"),
        ("toggleMode", Shortcut("m", modifiers: [.command, .shift], label: "Toggle Mode"), "View"),
        ("stackDone", Shortcut(.return, modifiers: .command, label: "Done"), "Stack"),
        ("stackHide", Shortcut("h", modifiers: [.command, .shift], label: "Hide"), "Stack"),
        ("stackMoveToBack", Shortcut("]", modifiers: [.command, .shift], label: "Move to Back"), "Stack"),
        ("splitHorizontal", Shortcut("d", modifiers: .command, label: "Split Horizontally"), "Splits"),
        ("splitVertical", Shortcut("d", modifiers: [.command, .shift], label: "Split Vertically"), "Splits"),
        ("selectTabLeft", Shortcut("[", modifiers: [.command, .shift], label: "Select Tab Left"), "Tabs"),
        ("selectTabRight", Shortcut("]", modifiers: [.command, .shift], label: "Select Tab Right"), "Tabs"),
        ("moveTabLeft", Shortcut(.leftArrow, modifiers: [.command, .shift], label: "Move Tab Left"), "Tabs"),
        ("moveTabRight", Shortcut(.rightArrow, modifiers: [.command, .shift], label: "Move Tab Right"), "Tabs"),
        ("nextProject", Shortcut(.tab, modifiers: .control, label: "Next Project"), "Projects"),
        ("prevProject", Shortcut(.tab, modifiers: [.control, .shift], label: "Previous Project"), "Projects"),
        ("settings", Shortcut(",", modifiers: .command, label: "Settings"), "App"),
        ("clearScrollback", Shortcut("k", modifiers: .command, label: "Clear Scrollback"), "App"),
    ]

    // MARK: - Resolution

    private static func resolve(_ id: String, default shortcut: Shortcut) -> Shortcut {
        guard let override = ForgeConfigStore.shared.config.shortcuts?[id] else { return shortcut }
        return Shortcut(from: override, label: shortcut.label)
    }
}

/// A keyboard shortcut definition with a human-readable tooltip string.
struct Shortcut {
    let key: KeyEquivalent
    let modifiers: EventModifiers
    let label: String

    init(_ character: Character, modifiers: EventModifiers, label: String) {
        self.key = KeyEquivalent(character)
        self.modifiers = modifiers
        self.label = label
    }

    init(_ key: KeyEquivalent, modifiers: EventModifiers, label: String) {
        self.key = key
        self.modifiers = modifiers
        self.label = label
    }

    init(_ string: String, modifiers: EventModifiers, label: String) {
        self.key = KeyEquivalent(string.first!)
        self.modifiers = modifiers
        self.label = label
    }

    init(from config: ForgeConfig.ShortcutConfig, label: String) {
        var mods: EventModifiers = []
        if config.modifiers.contains("control") { mods.insert(.control) }
        if config.modifiers.contains("option") { mods.insert(.option) }
        if config.modifiers.contains("shift") { mods.insert(.shift) }
        if config.modifiers.contains("command") { mods.insert(.command) }
        self.key = KeyEquivalent(config.key.first ?? Character("?"))
        self.modifiers = mods
        self.label = label
    }

    /// Human-readable string like "⇧⌘D" for use in tooltips.
    var hint: String {
        var parts: [String] = []
        if modifiers.contains(.control) { parts.append("⌃") }
        if modifiers.contains(.option) { parts.append("⌥") }
        if modifiers.contains(.shift) { parts.append("⇧") }
        if modifiers.contains(.command) { parts.append("⌘") }
        parts.append(keyLabel)
        return parts.joined()
    }

    private var keyLabel: String {
        switch key {
        case .leftArrow: return "←"
        case .rightArrow: return "→"
        case .upArrow: return "↑"
        case .downArrow: return "↓"
        case .tab: return "⇥"
        case .escape: return "⎋"
        case .return: return "↩"
        case .delete: return "⌫"
        case .space: return "Space"
        default:
            let char = String(key.character)
            return char.uppercased()
        }
    }
}
