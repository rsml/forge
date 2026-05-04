import SwiftUI

struct ThemeParser {
    static func loadAllThemes() -> [ThemeDefinition] {
        var themes: [ThemeDefinition] = []
        let searchPaths = [
            "/Applications/Ghostty.app/Contents/Resources/ghostty/themes",
            (NSHomeDirectory() as NSString).appendingPathComponent(".config/ghostty/themes"),
        ]
        let fm = FileManager.default
        for searchPath in searchPaths {
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
        var bg = Color(red: 0.1, green: 0.1, blue: 0.1)
        var fg = Color(red: 0.8, green: 0.8, blue: 0.8)
        var cursor: Color?
        var palette: [Int: Color] = [:]

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
        let name = id.replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
        return ThemeDefinition(id: id, name: name, background: bg, foreground: fg, cursor: cursor, ansiColors: ansiColors)
    }

    private static func parseColor(_ hex: String) -> Color? {
        var h = hex.trimmingCharacters(in: .whitespaces)
        if h.hasPrefix("#") { h = String(h.dropFirst()) }
        guard h.count == 6, let value = UInt64(h, radix: 16) else { return nil }
        let r = Double((value >> 16) & 0xFF) / 255.0
        let g = Double((value >> 8) & 0xFF) / 255.0
        let b = Double(value & 0xFF) / 255.0
        return Color(red: r, green: g, blue: b)
    }
}
