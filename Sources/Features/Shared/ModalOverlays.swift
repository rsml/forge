import SwiftUI

/// Presents all modal overlays (tab switcher, command palette, project picker, notifications)
/// based on AppState.activeModal. Extracts modal wiring from MainView.
struct ModalOverlays: ViewModifier {
    @Environment(AppState.self) private var appState

    func body(content: Content) -> some View {
        content
            .overlay {
                if appState.activeModal == .tabSwitcher {
                    topModal(width: 500) {
                        TabSwitcher(isPresented: modalBinding(.tabSwitcher))
                    }
                }
            }
            .overlay {
                if appState.activeModal == .commandPalette {
                    topModal(width: 500) {
                        CommandPalette(isPresented: modalBinding(.commandPalette))
                    }
                }
            }
            .overlay {
                if appState.activeModal == .projectPicker {
                    modalContainer(width: 520, maxHeight: 480) {
                        ProjectPickerView(onDismiss: { appState.dispatch(.dismissModal) })
                    }
                }
            }
            .overlay {
                if appState.activeModal == .notifications {
                    modalContainer(width: 380, maxHeight: 440) {
                        NotificationPanel(onDismiss: { appState.dispatch(.dismissModal) })
                    }
                }
            }
    }

    private func modalBinding(_ modal: AppState.Modal) -> Binding<Bool> {
        Binding(
            get: { appState.activeModal == modal },
            set: { if !$0 { appState.dispatch(.dismissModal) } }
        )
    }

    private func modalContainer<C: View>(width: CGFloat, maxHeight: CGFloat, @ViewBuilder content: @escaping () -> C) -> some View {
        ModalContainer(isPresented: modalBinding(appState.activeModal ?? .commandPalette),
                       width: width, maxHeight: maxHeight, content: content)
    }

    private func topModal<C: View>(width: CGFloat, @ViewBuilder content: @escaping () -> C) -> some View {
        ZStack(alignment: .top) {
            Color.black.opacity(0.25)
                .ignoresSafeArea()
                .onTapGesture { appState.dispatch(.dismissModal) }

            content()
                .frame(width: width)
                .fixedSize(horizontal: false, vertical: true)
                .background(.ultraThinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .shadow(color: .black.opacity(0.25), radius: 30, y: 8)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(Color.white.opacity(0.1), lineWidth: 0.5)
                )
                .padding(.top, 52)
        }
        .transition(.opacity.combined(with: .scale(scale: 0.97)))
    }
}
