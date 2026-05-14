import SwiftUI
import SwiftTerm

/// Embeds a single SwiftTermRenderer's NSView in SwiftUI. One per pane.
struct PaneTerminalView: NSViewRepresentable {
    let renderer: SwiftTermRenderer

    func makeNSView(context: Context) -> NSView {
        let view = renderer.view
        view.autoresizingMask = [.width, .height]
        DispatchQueue.main.async {
            view.window?.makeFirstResponder(view)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}
