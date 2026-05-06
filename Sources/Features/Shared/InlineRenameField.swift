import SwiftUI

/// Inline text field with a checkmark commit button.
struct InlineRenameField: View {
    @Binding var text: String
    var font: Font = .caption
    var onCancel: () -> Void = {}
    var onCommit: () -> Void
    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: 2) {
            TextField("Name", text: $text, onCommit: onCommit)
                .textFieldStyle(.plain)
                .font(font)
                .focused($isFocused)
                .padding(.horizontal, 4)
                .padding(.vertical, 2)
                .background(
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.primary.opacity(0.06))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 3)
                        .strokeBorder(Color.accentColor.opacity(0.4), lineWidth: 1)
                )

            IconButton(systemName: "checkmark", font: .system(size: 10, weight: .semibold)) {
                onCommit()
            }
            .frame(width: 20, height: 20)
        }
        .onKeyPress(.escape) { onCancel(); return .handled }
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                isFocused = true
            }
        }
    }
}
