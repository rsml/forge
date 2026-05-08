import SwiftUI

/// Blue dot = needs attention. No dot = everything fine.
/// Simple, binary. Bubbles up from panes → windows → sessions.
struct AttentionDot: View {
    @Environment(ForgeConfigStore.self) private var configStore
    let needsAttention: Bool

    private var size: CGFloat {
        CGFloat(configStore.config.notifications?.badgeSize ?? 8)
    }

    private var color: Color {
        let mode = configStore.config.notifications?.badgeColorMode ?? "accent"
        switch mode {
        case "theme":
            let themeColor = configStore.resolvedTheme?.cursor ?? configStore.resolvedTheme?.foreground
            return themeColor?.color ?? Color.accentColor
        case "custom":
            if let hex = configStore.config.notifications?.badgeCustomColor {
                return Color(hex: hex)
            }
            return Color.accentColor
        default:
            return Color.accentColor
        }
    }

    var body: some View {
        if needsAttention {
            Circle()
                .fill(color)
                .frame(width: size, height: size)
        }
    }
}

extension Color {
    init(hex: String) {
        let cleaned = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        var value: UInt64 = 0
        Scanner(string: cleaned).scanHexInt64(&value)
        if cleaned.count == 8 {
            let r = Double((value >> 24) & 0xFF) / 255
            let g = Double((value >> 16) & 0xFF) / 255
            let b = Double((value >> 8) & 0xFF) / 255
            let a = Double(value & 0xFF) / 255
            self.init(red: r, green: g, blue: b, opacity: a)
        } else {
            let r = Double((value >> 16) & 0xFF) / 255
            let g = Double((value >> 8) & 0xFF) / 255
            let b = Double(value & 0xFF) / 255
            self.init(red: r, green: g, blue: b)
        }
    }

    var hexString: String {
        guard let c = NSColor(self).usingColorSpace(.sRGB) else { return "#0000FF" }
        let r = Int(c.redComponent * 255)
        let g = Int(c.greenComponent * 255)
        let b = Int(c.blueComponent * 255)
        let a = Int(c.alphaComponent * 255)
        if a < 255 {
            return String(format: "#%02X%02X%02X%02X", r, g, b, a)
        }
        return String(format: "#%02X%02X%02X", r, g, b)
    }
}
