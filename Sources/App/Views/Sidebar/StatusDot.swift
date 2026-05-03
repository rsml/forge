import SwiftUI

struct StatusDot: View {
    let status: PaneStatus
    var size: CGFloat = 8

    var color: Color {
        switch status {
        case .idle: .gray
        case .running: .green
        case .needsAttention: .orange
        case .error: .red
        }
    }

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: size, height: size)
    }
}
