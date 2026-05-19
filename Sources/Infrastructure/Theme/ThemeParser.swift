import Foundation

struct ThemeParser {
    private static var searchPaths: [String] {
        var paths: [String] = []
        let fm = FileManager.default

        // 1. User override — listed first so it shadows bundled themes of the same name.
        let userOverride = (NSHomeDirectory() as NSString).appendingPathComponent(".config/forge/themes")
        paths.append(userOverride)

        // 2. Bundled themes directory (.app bundle resource path).
        if let bundleThemes = Bundle.main.resourceURL?.appendingPathComponent("themes").path,
           fm.fileExists(atPath: bundleThemes) {
            paths.append(bundleThemes)
        }

        // 3. Fallback for bare SPM builds (executable next to a `themes/` directory).
        if let spmThemes = Bundle.main.executableURL?
            .deletingLastPathComponent()
            .appendingPathComponent("themes").path,
           fm.fileExists(atPath: spmThemes) {
            paths.append(spmThemes)
        }

        return paths
    }

    static func loadTheme(id: String) -> ThemeDefinition? {
        for searchPath in Self.searchPaths {
            let path = (searchPath as NSString).appendingPathComponent(id)
            if let theme = parseThemeFile(path: path, id: id) {
                return theme
            }
        }
        if !id.isEmpty {
            ForgeLog.log("[theme] no file found for id '\(id)' — picker will fall back to default colors")
        }
        return nil
    }

    static func loadAllThemes() -> [ThemeDefinition] {
        var themes: [ThemeDefinition] = []
        let fm = FileManager.default
        for searchPath in Self.searchPaths {
            guard let files = try? fm.contentsOfDirectory(atPath: searchPath) else { continue }
            for file in files.sorted() {
                let fullPath = (searchPath as NSString).appendingPathComponent(file)
                guard !file.hasPrefix("."),
                      let theme = parseThemeFile(path: fullPath, id: file) else { continue }
                if !themes.contains(where: { $0.id == theme.id }) {
                    themes.append(theme)
                }
            }
        }
        return themes
    }

    static func parseThemeFile(path: String, id: String) -> ThemeDefinition? {
        guard let content = try? String(contentsOfFile: path, encoding: .utf8) else { return nil }
        var bg = ThemeColor(red: 0.1, green: 0.1, blue: 0.1)
        var fg = ThemeColor(red: 0.8, green: 0.8, blue: 0.8)
        var cursor: ThemeColor?
        var palette: [Int: ThemeColor] = [:]

        for line in content.split(separator: "\n", omittingEmptySubsequences: true) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.hasPrefix("#"), trimmed.contains("=") else { continue }
            let parts = trimmed.split(separator: "=", maxSplits: 1)
            guard parts.count == 2 else { continue }
            let key = parts[0].trimmingCharacters(in: .whitespaces)
            let value = parts[1].trimmingCharacters(in: .whitespaces)

            switch key {
            case "background":
                bg = parseColor(value) ?? bg
            case "foreground":
                fg = parseColor(value) ?? fg
            case "cursor-color":
                cursor = parseColor(value)
            default:
                if key.hasPrefix("palette") {
                    let paletteParts = value.split(separator: "=", maxSplits: 1)
                    if paletteParts.count == 2,
                       let idx = Int(paletteParts[0]),
                       let color = parseColor(String(paletteParts[1]))
                    {
                        palette[idx] = color
                    }
                }
            }
        }

        let ansiColors = (0..<16).map { palette[$0] ?? fg }
        let baseName = id.hasSuffix(".conf") ? String(id.dropLast(5)) : id
        let name = baseName.replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
        return ThemeDefinition(id: id, name: name, background: bg, foreground: fg, cursor: cursor, ansiColors: ansiColors)
    }

    private static func parseColor(_ hex: String) -> ThemeColor? {
        var h = hex.trimmingCharacters(in: .whitespaces)
        if h.hasPrefix("#") { h = String(h.dropFirst()) }
        guard h.count == 6, let value = UInt64(h, radix: 16) else { return nil }
        let r = Double((value >> 16) & 0xFF) / 255.0
        let g = Double((value >> 8) & 0xFF) / 255.0
        let b = Double(value & 0xFF) / 255.0
        return ThemeColor(red: r, green: g, blue: b)
    }
}
