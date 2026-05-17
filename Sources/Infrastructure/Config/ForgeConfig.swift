import Foundation

struct ForgeConfig: Codable {
    var projects: [ProjectConfig]
    var recentDirectories: [String]
    var theme: ThemeConfig?
    var uiState: UIState?
    var general: GeneralSettings?
    var appearance: AppearanceSettings?
    var terminal: TerminalSettings?
    var shortcuts: [String: ShortcutConfig]?
    var projectOpenCounts: [String: Int]?
    var primaryFont: FontConfig?
    var secondaryFont: FontConfig?
    var terminalFont: FontConfig?
    var notifications: NotificationSettings?
    var stackView: StackViewSettings?

    struct FontConfig: Codable {
        var family: String?
        var size: Int?
        var useLigatures: Bool?
        var lineHeight: Double?
    }

    struct ProjectConfig: Codable {
        var name: String
        var path: String
        var color: String?
        var pinned: Bool?
        var sortOrder: Int?
    }

    struct ThemeConfig: Codable {
        var source: String?
    }

    struct GeneralSettings: Codable {
        var defaultShell: String?
        var defaultProjectDir: String?
        var autoRestore: Bool?
        var confirmBeforeClose: Bool?
        var warnOnCloseProject: Bool?
        var warnOnCloseTab: Bool?
        var warnOnMoveTab: Bool?
        var sidebarPosition: String?    // "left" or "right"
        var tabBarPosition: String?     // "top" or "bottom"
        var tabHighlightColorMode: String?  // "accent" (default), "theme", "custom"
        var tabHighlightCustomColor: String? // hex color string, e.g. "#FF0000"
        var nativePaneRendering: Bool?
        var nativePTY: Bool?
        // Legacy — migrated to NotificationSettings on load
        var notificationsEnabled: Bool?
        var notificationSound: String?
    }

    struct NotificationSettings: Codable {
        var enabled: Bool?              // defaults to false
        var sound: String?              // system sound name or custom file path
        var activeTabBanner: Bool?      // show notification banner for active tab (default false)
        var activeTabSound: Bool?       // play sound for active tab (default true)
        var badgeColorMode: String?     // "accent" (default), "theme", "custom"
        var badgeCustomColor: String?   // hex color string, e.g. "#FF0000"
        var badgeSize: Double?          // default 8
    }

    struct TerminalSettings: Codable {
        var fontFamily: String?
        var fontSize: Int?
        var scrollbackLines: Int?
        var tabBarPosition: String?
        var useTmuxPersistence: Bool?
        var tmuxConfigOverride: String?
    }

    struct AppearanceSettings: Codable {
        var fontFamily: String?
        var fontSize: Int?
        var tabBarPosition: String?
    }

    struct ShortcutConfig: Codable, Equatable {
        var key: String
        var modifiers: [String]
    }

    struct UIState: Codable {
        var activeProjectName: String?
        var activeTabIndex: Int?
        var sidebarVisible: Bool?
        var expandedProjectNames: [String]?
    }

    struct StackViewSettings: Codable, Equatable {
        var toolbarPosition: String?        // "top" or "bottom"
        var bringToForeground: String?      // "never" or "always"
        var notify: String?                 // "always" or "never"
        var notifyInStackMode: Bool?        // show notifications in stack mode (default false)
        var notificationSound: String?      // system sound name or custom file path
        var hiddenTabUUIDs: [String]?    // persisted hidden set
        var contentPatterns: [String]?      // user-defined patterns merged with defaults

        public init() {}
    }

    static let defaultConfig = ForgeConfig(
        projects: [],
        recentDirectories: [],
        theme: ThemeConfig(source: "ghostty-seti")
    )

    static var configURL: URL {
        URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent(".config/forge/config.json")
    }

    static func load() -> ForgeConfig {
        guard let data = try? Data(contentsOf: configURL),
              var config = try? JSONDecoder().decode(ForgeConfig.self, from: data) else {
            return defaultConfig
        }
        config.migrateNotificationSettings()
        return config
    }

    /// One-time migration: move legacy notification fields from GeneralSettings to NotificationSettings.
    mutating func migrateNotificationSettings() {
        let legacyEnabled = general?.notificationsEnabled
        let legacySound = general?.notificationSound
        guard notifications == nil, legacyEnabled != nil || legacySound != nil else { return }

        notifications = NotificationSettings(
            enabled: legacyEnabled,
            sound: legacySound
        )
        general?.notificationsEnabled = nil
        general?.notificationSound = nil
        save()
    }

    func save() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(self) else { return }
        let dir = ForgeConfig.configURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try? data.write(to: ForgeConfig.configURL)
    }
}
