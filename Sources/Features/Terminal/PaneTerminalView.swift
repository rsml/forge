import SwiftUI

/// Embeds a TerminalRenderer's NSView in SwiftUI. One per pane.
/// SwiftTerm's TerminalView auto-calculates cols/rows from its frame via
/// setFrameSize → processSizeChange → sizeChanged delegate callback.
/// We rely on that callback to send resize-pane to tmux.
struct PaneTerminalView: NSViewRepresentable {
    let renderer: any TerminalRenderer

    func makeNSView(context: Context) -> NSView {
        let termView = renderer.view
        termView.translatesAutoresizingMaskIntoConstraints = false

        // Wrapper so SwiftUI constraint-based layout drives the TerminalView frame
        let wrapper = NSView(frame: .zero)
        wrapper.addSubview(termView)
        NSLayoutConstraint.activate([
            termView.leadingAnchor.constraint(equalTo: wrapper.leadingAnchor),
            termView.trailingAnchor.constraint(equalTo: wrapper.trailingAnchor),
            termView.topAnchor.constraint(equalTo: wrapper.topAnchor),
            termView.bottomAnchor.constraint(equalTo: wrapper.bottomAnchor),
        ])

        DispatchQueue.main.async {
            wrapper.window?.makeFirstResponder(termView)
        }

        return wrapper
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}
