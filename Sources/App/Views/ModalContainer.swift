import SwiftUI

struct ModalContainer<Content: View>: View {
    @Binding var isPresented: Bool
    var width: CGFloat = 520
    var maxHeight: CGFloat = 480
    @ViewBuilder var content: () -> Content

    var body: some View {
        ZStack {
            Color.black.opacity(0.25)
                .ignoresSafeArea()
                .onTapGesture { isPresented = false }

            content()
                .frame(width: width)
                .frame(maxHeight: maxHeight)
                .background(.ultraThinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .shadow(color: .black.opacity(0.25), radius: 30, y: 8)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(Color.white.opacity(0.1), lineWidth: 0.5)
                )
        }
        .transition(.opacity.combined(with: .scale(scale: 0.97)))
    }
}
