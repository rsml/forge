import SwiftUI
import ForgeCore

/// Default keyboard shortcuts for all Forge actions.
/// Overrides are resolved from ForgeConfigStore at access time.
@MainActor
enum KeyboardShortcuts {
    // MARK: - File
    static var newProject: Shortcut { resolve("newProject", default: Shortcut("n", modifiers: .command, label: "New Project")) }
    static var newTab: Shortcut { resolve("newTab", default: Shortcut("t", modifiers: .command, label: "New Tab")) }
    static var closePane: Shortcut { resolve("closePane", default: Shortcut("w", modifiers: .command, label: "Close Tab / Pane")) }
    static var closeProject: Shortcut { resolve("closeProject", default: Shortcut("w", modifiers: [.command, .shift], label: "Close Project")) }
    static var renameTab: Shortcut { resolve("renameTab", default: Shortcut("r", modifiers: .command, label: "Rename Tab")) }
    static var renameProject: Shortcut { resolve("renameProject", default: Shortcut("r", modifiers: [.command, .shift], label: "Rename Project")) }

    // MARK: - View
    static var toggleSidebar: Shortcut { resolve("toggleSidebar", default: Shortcut("b", modifiers: .command, label: "Toggle Sidebar")) }
    static var tabSwitcher: Shortcut { resolve("tabSwitcher", default: Shortcut("p", modifiers: .command, label: "Tab Switcher")) }
    static var commandPalette: Shortcut { resolve("commandPalette", default: Shortcut("p", modifiers: [.command, .shift], label: "Command Palette")) }
    static var notifications: Shortcut { resolve("notifications", default: Shortcut("n", modifiers: [.command, .shift], label: "Notifications")) }
    static var toggleMode: Shortcut { resolve("toggleMode", default: Shortcut("m", modifiers: [.command, .shift], label: "Toggle Mode")) }

    // MARK: - Notifications
    static var toggleNotifications: Shortcut { resolve("toggleNotifications", default: Shortcut("h", modifiers: [.command, .shift], label: "Toggle Notifications")) }

    // MARK: - Stack
    static var stackDone: Shortcut { resolve("stackDone", default: Shortcut(.return, modifiers: .command, label: "Done")) }
    static var stackHide: Shortcut { resolve("stackHide", default: Shortcut("h", modifiers: [.command, .shift], label: "Hide")) }
    static var stackMoveToBack: Shortcut { resolve("stackMoveToBack", default: Shortcut("]", modifiers: [.control, .shift], label: "Move to Back")) }

    // MARK: - Splits
    static var splitHorizontal: Shortcut { resolve("splitHorizontal", default: Shortcut("d", modifiers: .command, label: "Split Horizontally")) }
    static var splitVertical: Shortcut { resolve("splitVertical", default: Shortcut("d", modifiers: [.command, .shift], label: "Split Vertically")) }

    // MARK: - Tabs
    static var selectTabLeft: Shortcut { resolve("selectTabLeft", default: Shortcut(.leftArrow, modifiers: [.command, .shift], label: "Previous Tab")) }
    static var selectTabRight: Shortcut { resolve("selectTabRight", default: Shortcut(.rightArrow, modifiers: [.command, .shift], label: "Next Tab")) }
    static var moveTabLeft: Shortcut { resolve("moveTabLeft", default: Shortcut("[", modifiers: [.command, .shift], label: "Move Tab Back")) }
    static var moveTabRight: Shortcut { resolve("moveTabRight", default: Shortcut("]", modifiers: [.command, .shift], label: "Move Tab Forward")) }

    // MARK: - Projects
    static var nextProject: Shortcut { resolve("nextProject", default: Shortcut(.rightArrow, modifiers: [.option, .shift], label: "Next Project")) }
    static var prevProject: Shortcut { resolve("prevProject", default: Shortcut(.leftArrow, modifiers: [.option, .shift], label: "Previous Project")) }
    static var moveProjectBack: Shortcut { resolve("moveProjectBack", default: Shortcut("[", modifiers: [.option, .shift], label: "Move Project Back")) }
    static var moveProjectForward: Shortcut { resolve("moveProjectForward", default: Shortcut("]", modifiers: [.option, .shift], label: "Move Project Forward")) }

    // MARK: - App
    static var settings: Shortcut { resolve("settings", default: Shortcut(",", modifiers: .command, label: "Open Settings")) }
    static var clearScrollback: Shortcut { resolve("clearScrollback", default: Shortcut("k", modifiers: .command, label: "Clear Scrollback")) }

    // MARK: - All Defaults (for settings UI)
    static let allDefaults: [(id: String, shortcut: Shortcut, category: String)] = [
        // App
        ("settings", Shortcut(",", modifiers: .command, label: "Open Settings"), "App"),
        ("toggleSidebar", Shortcut("b", modifiers: .command, label: "Toggle Sidebar"), "App"),
        ("tabSwitcher", Shortcut("p", modifiers: .command, label: "Tab Switcher"), "App"),
        ("commandPalette", Shortcut("p", modifiers: [.command, .shift], label: "Command Palette"), "App"),
        ("notifications", Shortcut("n", modifiers: [.command, .shift], label: "Notifications"), "App"),
        ("toggleMode", Shortcut("m", modifiers: [.command, .shift], label: "Toggle Mode"), "App"),
        ("toggleNotifications", Shortcut("h", modifiers: [.command, .shift], label: "Toggle Notifications"), "Tabs"),
        // Projects
        ("newProject", Shortcut("n", modifiers: .command, label: "New Project"), "Projects"),
        ("closeProject", Shortcut("w", modifiers: [.command, .shift], label: "Close Project"), "Projects"),
        ("renameProject", Shortcut("r", modifiers: [.command, .shift], label: "Rename Project"), "Projects"),
        ("prevProject", Shortcut(.leftArrow, modifiers: [.option, .shift], label: "Previous Project"), "Projects"),
        ("nextProject", Shortcut(.rightArrow, modifiers: [.option, .shift], label: "Next Project"), "Projects"),
        ("moveProjectBack", Shortcut("[", modifiers: [.option, .shift], label: "Move Project Back"), "Projects"),
        ("moveProjectForward", Shortcut("]", modifiers: [.option, .shift], label: "Move Project Forward"), "Projects"),
        // Tabs
        ("newTab", Shortcut("t", modifiers: .command, label: "New Tab"), "Tabs"),
        ("closePane", Shortcut("w", modifiers: .command, label: "Close Tab / Pane"), "Tabs"),
        ("renameTab", Shortcut("r", modifiers: .command, label: "Rename Tab"), "Tabs"),
        ("selectTabLeft", Shortcut(.leftArrow, modifiers: [.command, .shift], label: "Previous Tab"), "Tabs"),
        ("selectTabRight", Shortcut(.rightArrow, modifiers: [.command, .shift], label: "Next Tab"), "Tabs"),
        ("moveTabLeft", Shortcut("[", modifiers: [.command, .shift], label: "Move Tab Back"), "Tabs"),
        ("moveTabRight", Shortcut("]", modifiers: [.command, .shift], label: "Move Tab Forward"), "Tabs"),
        // Terminal
        ("splitHorizontal", Shortcut("d", modifiers: .command, label: "Split Horizontally"), "Terminal"),
        ("splitVertical", Shortcut("d", modifiers: [.command, .shift], label: "Split Vertically"), "Terminal"),
        ("clearScrollback", Shortcut("k", modifiers: .command, label: "Clear Scrollback"), "Terminal"),
        // Stack Mode
        ("stackDone", Shortcut(.return, modifiers: .command, label: "Done"), "Stack Mode"),
        ("stackHide", Shortcut("h", modifiers: [.command, .shift], label: "Hide"), "Stack Mode"),
        ("stackMoveToBack", Shortcut("]", modifiers: [.control, .shift], label: "Move to Back"), "Stack Mode"),
    ]

    // MARK: - Resolution

    /// Set once by AppDelegate at startup. Avoids `.shared` access from static context.
    static weak var config: ForgeConfigStore?

    private static func resolve(_ id: String, default shortcut: Shortcut) -> Shortcut {
        guard let override = config?.config.shortcuts?[id] else { return shortcut }
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
            let char = key.character
            if modifiers.contains(.shift), let unshifted = Self.unshiftMap[char] {
                return String(unshifted).uppercased()
            }
            return String(char).uppercased()
        }
    }

    /// Maps shifted characters back to their unshifted key (US keyboard layout).
    private static let unshiftMap: [Character: Character] = [
        "{": "[", "}": "]", "<": ",", ">": ".",
        "~": "`", "!": "1", "@": "2", "#": "3",
        "$": "4", "%": "5", "^": "6", "&": "7",
        "*": "8", "(": "9", ")": "0", "_": "-",
        "+": "=", "|": "\\", ":": ";", "\"": "'", "?": "/",
    ]
}
