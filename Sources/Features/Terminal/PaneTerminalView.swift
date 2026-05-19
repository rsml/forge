import SwiftUI
import ForgeCore

/// Embeds a TerminalRenderer's NSView in SwiftUI. One per pane.
/// SwiftTerm's TerminalView auto-calculates cols/rows from its frame via
/// setFrameSize → processSizeChange → sizeChanged delegate callback.
/// We rely on that callback to send resize-pane to tmux.
///
/// Attaches an AppKit `NSMenu` to the renderer's NSView on every update so
/// the right-click context menu fires. SwiftUI's `.contextMenu` modifier
/// can't see right-clicks here because the renderer's NSView intercepts them
/// to forward to the ghostty surface — `GhosttyNSView.rightMouseDown` pops
/// up `self.menu` directly when present.
struct PaneTerminalView: NSViewRepresentable {
    let renderer: any TerminalRenderer
    /// Non-nil when this view is rendered inside a domain pane (TerminalArea
    /// / PaneSplitView). The legacy tmux path also uses this view but does
    /// not need a context menu, so `pane` is optional.
    var pane: Pane?

    @Environment(WorkspaceController.self) private var controller
    @Environment(AppState.self) private var appState
    @Environment(AttentionManager.self) private var attention

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

    func updateNSView(_ nsView: NSView, context: Context) {
        // Refresh the context menu on every update so dynamic labels (Convert,
        // Close Tab/Pane, Enable/Disable Notifications) re-evaluate when state
        // changes. AppKit caches the menu; reassigning is cheap.
        guard let pane,
              let (project, tab, _) = controller.workspace.findPane(byId: pane.id)
        else {
            renderer.view.menu = nil
            return
        }
        renderer.view.menu = PaneContextNSMenu.make(
            controller: controller,
            appState: appState,
            attention: attention,
            project: project,
            tab: tab,
            pane: pane
        )
    }
}
