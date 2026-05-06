import SwiftUI

/// Presents all modal overlays (command palette, project picker, notifications)
/// based on AppState.activeModal. Extracts modal wiring from MainView.
struct ModalOverlays: ViewModifier {
    @Environment(AppState.self) private var appState

    func body(content: Content) -> some View {
        content
            .overlay {
                if appState.activeModal == .commandPalette {
                    modalContainer(width: 500, maxHeight: 400) {
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
}
