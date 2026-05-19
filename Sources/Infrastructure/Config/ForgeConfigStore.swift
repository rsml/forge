import SwiftUI
import ForgeCore

extension ForgeConfig.FontConfig {
    func resolved(defaultSize: Int = 13) -> Font {
        let family = self.family ?? ".AppleSystemUIFont"
        let size = CGFloat(self.size ?? defaultSize)
        return .custom(family, size: size)
    }
}

extension ForgeConfigStore {
    var primaryFont: Font {
        (config.primaryFont ?? ForgeConfig.FontConfig()).resolved(defaultSize: 13)
    }
    var secondaryFont: Font {
        (config.secondaryFont ?? ForgeConfig.FontConfig()).resolved(defaultSize: 11)
    }
    var tabHighlightColor: Color {
        let mode = config.general?.tabHighlightColorMode ?? "accent"
        switch mode {
        case "theme":
            let themeColor = resolvedTheme?.cursor ?? resolvedTheme?.foreground
            return themeColor?.color ?? Color.accentColor
        case "custom":
            if let hex = config.general?.tabHighlightCustomColor {
                return Color(hex: hex)
            }
            return Color.accentColor
        default:
            return Color.accentColor
        }
    }
}

@Observable @MainActor
final class ForgeConfigStore {
    static let shared = ForgeConfigStore(themeLoader: { ThemeParser.loadTheme(id: $0) })
    private(set) var config: ForgeConfig

    /// Measured from the actual NSWindow; updated by AppDelegate.
    var titlebarHeight: CGFloat = 28

    /// Current sidebar width; updated by MainView during resize so AppDelegate can track it.
    var sidebarWidth: CGFloat = 160

    /// Stack mode vs list mode for the sidebar project view.
    var isStackMode: Bool = false

    private let themeLoader: (String) -> ThemeDefinition?

    init(themeLoader: @escaping (String) -> ThemeDefinition?) {
        self.themeLoader = themeLoader
        config = ForgeConfig.load()
    }

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
        let result = resolveThemeFromConfig()
        _resolvedTheme = .some(result)
        return result
    }

    private func resolveThemeFromConfig() -> ThemeDefinition? {
        guard let themeId = config.theme?.source else { return nil }
        return themeLoader(themeId)
    }
}
