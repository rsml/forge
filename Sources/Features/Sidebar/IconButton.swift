import SwiftUI

/// A plain icon button with a hover effect (secondary → primary).
/// Handles its own hover state internally.
struct IconButton: View {
    let systemName: String
    var font: Font = .system(size: 11, weight: .medium)
    var action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(font)
                .foregroundStyle(isHovered ? .primary : .secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}
