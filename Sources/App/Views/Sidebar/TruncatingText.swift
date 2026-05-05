import SwiftUI

/// A single-line Text that shows a tooltip with the full string only when truncated.
struct TruncatingText: View {
    let text: String
    let font: Font

    @State private var isTruncated = false

    init(_ text: String, font: Font) {
        self.text = text
        self.font = font
    }

    var body: some View {
        Text(text)
            .font(font)
            .lineLimit(1)
            .background(
                // Invisible full-size text to measure if truncation occurred
                Text(text)
                    .font(font)
                    .lineLimit(1)
                    .fixedSize()
                    .hidden()
                    .background(GeometryReader { full in
                        Color.clear.preference(key: FullWidthKey.self, value: full.size.width)
                    })
            )
            .overlay(
                GeometryReader { visible in
                    Color.clear.preference(key: VisibleWidthKey.self, value: visible.size.width)
                }
            )
            .onPreferenceChange(FullWidthKey.self) { fullWidth in
                checkTruncation(fullWidth: fullWidth)
            }
            .onPreferenceChange(VisibleWidthKey.self) { visibleWidth in
                checkTruncation(visibleWidth: visibleWidth)
            }
            .help(isTruncated ? text : "")
    }

    @State private var lastFullWidth: CGFloat = 0
    @State private var lastVisibleWidth: CGFloat = 0

    private func checkTruncation(fullWidth: CGFloat? = nil, visibleWidth: CGFloat? = nil) {
        if let fullWidth { lastFullWidth = fullWidth }
        if let visibleWidth { lastVisibleWidth = visibleWidth }
        isTruncated = lastFullWidth > lastVisibleWidth + 1
    }
}

private struct FullWidthKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}

private struct VisibleWidthKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}
