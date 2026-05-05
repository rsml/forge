import SwiftUI
import ForgeDomain

@Observable @MainActor
final class ForgeConfigStore {
    static let shared = ForgeConfigStore()
    private(set) var config: ForgeConfig

    /// Measured from the actual NSWindow; updated by AppDelegate.
    var titlebarHeight: CGFloat = 28

    /// Current sidebar width; updated by MainView during resize so AppDelegate can track it.
    var sidebarWidth: CGFloat = 160

    /// Stack mode vs list mode for the sidebar project view.
    var isStackMode: Bool = false

    private init() { config = ForgeConfig.load() }

    func update(_ mutate: (inout ForgeConfig) -> Void) {
        mutate(&config)
        config.save()
        _resolvedTheme = nil // invalidate cache
        NotificationCenter.default.post(name: .forgeConfigChanged, object: nil)
    }

    // MARK: - Theme Resolution (cached)

    private var _resolvedTheme: ThemeDefinition??  // nil = not loaded, .some(nil) = no theme
    var resolvedTheme: ThemeDefinition? {
        if let cached = _resolvedTheme { return cached }
        let result = Self.loadTheme(id: config.theme?.source)
        _resolvedTheme = .some(result)
        return result
    }

    private static func loadTheme(id: String?) -> ThemeDefinition? {
        guard let themeId = id else { return nil }
        let searchPaths = [
            "/Applications/Ghostty.app/Contents/Resources/ghostty/themes",
            (NSHomeDirectory() as NSString).appendingPathComponent(".config/ghostty/themes"),
        ]
        for searchPath in searchPaths {
            let path = (searchPath as NSString).appendingPathComponent(themeId)
            if let theme = ThemeParser.parseThemeFile(path: path, id: themeId) {
                return theme
            }
        }
        return nil
    }
}
