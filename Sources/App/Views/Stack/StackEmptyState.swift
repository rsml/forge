import SwiftUI

struct StackEmptyState: View {
    var body: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "checkmark.circle")
                .font(.system(size: 48))
                .opacity(0.3)
            Text("Nothing needs your attention")
                .font(.headline)
            Text("Terminals will appear here when they need input")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Button("Switch to List View") {
                ForgeConfigStore.shared.isStackMode = false
            }
            .buttonStyle(.bordered)
            .padding(.top, 8)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
