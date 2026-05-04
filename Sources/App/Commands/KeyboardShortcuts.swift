import SwiftUI

/// Default keyboard shortcuts for all Forge actions.
/// These serve as defaults and will be overridable via settings.
enum KeyboardShortcuts {
    // MARK: - File
    static let newProject = Shortcut("n", modifiers: .command, label: "New Project")
    static let newTab = Shortcut("t", modifiers: .command, label: "New Tab")
    static let closePane = Shortcut("w", modifiers: .command, label: "Close Pane")
    static let closeProject = Shortcut("w", modifiers: [.command, .shift], label: "Close Project")

    // MARK: - View
    static let toggleSidebar = Shortcut("b", modifiers: .command, label: "Toggle Sidebar")
    static let commandPalette = Shortcut("p", modifiers: .command, label: "Command Palette")
    static let notifications = Shortcut("n", modifiers: [.command, .shift], label: "Notifications")

    // MARK: - Splits
    static let splitHorizontal = Shortcut("d", modifiers: .command, label: "Split Horizontally")
    static let splitVertical = Shortcut("d", modifiers: [.command, .shift], label: "Split Vertically")

    // MARK: - Tabs
    static let selectTabLeft = Shortcut("[", modifiers: [.command, .shift], label: "Select Tab Left")
    static let selectTabRight = Shortcut("]", modifiers: [.command, .shift], label: "Select Tab Right")
    static let moveTabLeft = Shortcut(.leftArrow, modifiers: [.command, .shift], label: "Move Tab Left")
    static let moveTabRight = Shortcut(.rightArrow, modifiers: [.command, .shift], label: "Move Tab Right")

    // MARK: - Projects
    static let nextProject = Shortcut(.tab, modifiers: .control, label: "Next Project")
    static let prevProject = Shortcut(.tab, modifiers: [.control, .shift], label: "Previous Project")

    // MARK: - App
    static let settings = Shortcut(",", modifiers: .command, label: "Settings")
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

    /// Label with shortcut hint, e.g. "Split Horizontally (⌘D)"
    var tooltip: String {
        "\(label) (\(hint))"
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
