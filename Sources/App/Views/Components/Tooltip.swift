import SwiftUI

// MARK: - Tooltip View

private struct TooltipView: View {
    let label: String
    let hint: String?

    var body: some View {
        VStack(spacing: 2) {
            Text(label)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.white)
            if let hint {
                Text(hint)
                    .font(.system(size: 11, weight: .regular))
                    .foregroundStyle(.white.opacity(0.7))
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color.black.opacity(0.85))
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .shadow(color: .black.opacity(0.25), radius: 4, y: 2)
    }
}

// MARK: - Tooltip Modifier

private struct TooltipModifier: ViewModifier {
    let label: String
    let hint: String?
    let delay: TimeInterval

    @State private var isHovered = false
    @State private var isVisible = false
    @State private var showTask: Task<Void, Never>?

    func body(content: Content) -> some View {
        content
            .onHover { hovering in
                isHovered = hovering
                if hovering {
                    showTask = Task { @MainActor in
                        try? await Task.sleep(for: .seconds(delay))
                        guard !Task.isCancelled else { return }
                        withAnimation(.easeIn(duration: 0.15)) {
                            isVisible = true
                        }
                    }
                } else {
                    showTask?.cancel()
                    showTask = nil
                    withAnimation(.easeOut(duration: 0.1)) {
                        isVisible = false
                    }
                }
            }
            .overlay(alignment: .bottom) {
                if isVisible {
                    TooltipView(label: label, hint: hint)
                        .fixedSize()
                        .offset(y: 28)
                        .zIndex(1000)
                        .transition(.opacity)
                        .allowsHitTesting(false)
                }
            }
    }
}

// MARK: - View Extensions

extension View {
    func tooltip(_ text: String?) -> some View {
        if let text, !text.isEmpty {
            return AnyView(modifier(TooltipModifier(label: text, hint: nil, delay: 0.5)))
        }
        return AnyView(self)
    }

    func tooltip(_ shortcut: Shortcut) -> some View {
        modifier(TooltipModifier(label: shortcut.label, hint: shortcut.hint, delay: 0.5))
    }
}
