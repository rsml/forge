import SwiftUI

struct ThemePreviewCard: View {
    let theme: ThemeDefinition
    let isSelected: Bool
    let onSelect: () -> Void

    var body: some View {
        VStack(spacing: 4) {
            ZStack {
                RoundedRectangle(cornerRadius: 6)
                    .fill(theme.background)

                VStack(alignment: .leading, spacing: 2) {
                    ForEach(0..<3, id: \.self) { row in
                        HStack(spacing: 4) {
                            ForEach(0..<4, id: \.self) { col in
                                let idx = row * 4 + col
                                let color = idx < theme.ansiColors.count ? theme.ansiColors[idx] : theme.foreground
                                RoundedRectangle(cornerRadius: 2)
                                    .fill(color)
                                    .frame(height: 4)
                            }
                        }
                    }
                    Text("~/project $")
                        .font(.system(size: 8, design: .monospaced))
                        .foregroundStyle(theme.foreground)
                }
                .padding(8)
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
    }
}
