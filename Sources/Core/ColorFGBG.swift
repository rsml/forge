/// Rec.601 luminance check. Matches Forge's `NSColor.isLight` so the AppKit
/// chrome, COLORFGBG, and the terminal color-scheme report all agree on what
/// "light" means.
public enum BackgroundLuminance {
    public static func isLight(red: Double, green: Double, blue: Double) -> Bool {
        0.299 * red + 0.587 * green + 0.114 * blue > 0.5
    }
}

/// COLORFGBG env var value derived from terminal background luminance.
/// TUIs (e.g. Claude Code's `theme: "auto"` mode) read this to choose light vs dark
/// without querying the terminal — when unset, many default to dark.
///
/// Format: `"fg;bg"` where each side is an ANSI color index 0–15. The bg side
/// is what consumers check: 0–6 or 8 → dark; 7 or 9–15 → light.
public enum ColorFGBG {
    public static func value(red: Double, green: Double, blue: Double) -> String {
        BackgroundLuminance.isLight(red: red, green: green, blue: blue) ? "0;15" : "15;0"
    }
}
