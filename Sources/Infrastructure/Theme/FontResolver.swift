import AppKit

/// Resolves the best available monospaced font for the terminal.
///
/// Priority:
/// 1. Font family from Forge config
/// 2. Font declared in ~/.config/ghostty/config (`font-family = ...`)
/// 3. Common Nerd Font families installed on the system
/// 4. System monospaced font (final fallback, no Nerd Font glyphs)
enum FontResolver {
    static func resolveTerminalFont(family: String? = nil, size: CGFloat) -> NSFont {
        if let family, let font = NSFont(name: family, size: size) {
            return font
        }
        let candidates = (ghosttyFontFamily().map { [$0] } ?? []) + nerdFontFallbacks
        for candidate in candidates {
            if let font = NSFont(name: candidate, size: size) {
                return font
            }
        }
        return NSFont.monospacedSystemFont(ofSize: size, weight: .regular)
    }

    // MARK: - Private

    private static let nerdFontFallbacks = [
        "Dank Mono",
        "MesloLGS NF",
        "MesloLGM Nerd Font",
        "JetBrainsMono Nerd Font",
        "JetBrains Mono NL",
        "FiraCode Nerd Font",
        "Hack Nerd Font",
        "SauceCodePro Nerd Font",
        "DejaVuSansMono Nerd Font",
    ]

    private static func ghosttyFontFamily() -> String? {
        let configPath = (NSHomeDirectory() as NSString)
            .appendingPathComponent(".config/ghostty/config")
        guard let contents = try? String(contentsOfFile: configPath, encoding: .utf8) else {
            return nil
        }
        for line in contents.split(separator: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix("font-family"), trimmed.contains("=") else { continue }
            let parts = trimmed.split(separator: "=", maxSplits: 1)
            guard parts.count == 2 else { continue }
            let value = parts[1].trimmingCharacters(in: .whitespaces)
            if !value.isEmpty { return value }
        }
        return nil
    }
}
