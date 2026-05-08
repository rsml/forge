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
        var rgb: UInt64 = 0
        Scanner(string: cleaned).scanHexInt64(&rgb)
        let r = Double((rgb >> 16) & 0xFF) / 255
        let g = Double((rgb >> 8) & 0xFF) / 255
        let b = Double(rgb & 0xFF) / 255
        self.init(red: r, green: g, blue: b)
    }
}
