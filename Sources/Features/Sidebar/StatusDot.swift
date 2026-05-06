import SwiftUI

/// Blue dot = needs attention. No dot = everything fine.
/// Simple, binary. Bubbles up from panes → windows → sessions.
struct AttentionDot: View {
    let needsAttention: Bool
    var size: CGFloat = 8

    var body: some View {
        if needsAttention {
            Circle()
                .fill(Color.accentColor)
                .frame(width: size, height: size)
        }
    }
}
