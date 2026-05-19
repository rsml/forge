import SwiftUI

struct ThemePreviewCard: View {
    let theme: ThemeDefinition
    let isSelected: Bool
    let onSelect: () -> Void

    var body: some View {
        VStack(spacing: 4) {
            ZStack {
                RoundedRectangle(cornerRadius: 6)
                    .fill(theme.background.color)

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 0) {
                        Text("~ ")
                            .foregroundStyle(colorAt(2))
                        Text("$ ")
                            .foregroundStyle(theme.foreground.color)
                        Text("ls -la")
                            .foregroundStyle(theme.foreground.color)
                    }

                    HStack(spacing: 0) {
                        Text("src/")
                            .foregroundStyle(colorAt(4))
                        Text("  ")
                        Text("README")
                            .foregroundStyle(theme.foreground.color)
                    }

                    Text("error: not found")
                        .foregroundStyle(colorAt(1))
                }
                .font(.system(size: 7, design: .monospaced))
                .padding(8)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
            .frame(height: 70)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(isSelected ? Color.accentColor : Color.clear, lineWidth: 2)
            )

            Text(theme.name)
                .font(.caption2)
                .lineLimit(1)
                .truncationMode(.tail)
                .foregroundStyle(isSelected ? .primary : .secondary)
        }
        .contentShape(Rectangle())
        .onTapGesture { onSelect() }
        .onHover { hovering in
            if hovering {
                NotificationCenter.default.post(
                    name: .forgeThemeHoverPreview,
                    object: nil,
                    userInfo: ["themeId": theme.id])
            } else {
                NotificationCenter.default.post(
                    name: .forgeThemeHoverEnded, object: nil)
            }
        }
    }

    private func colorAt(_ index: Int) -> Color {
        index < theme.ansiColors.count ? theme.ansiColors[index].color : theme.foreground.color
    }
}
