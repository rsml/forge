import AppKit

/// Common interface for any pane-content renderer (terminal, browser, future kinds).
/// Concrete adapters refine this protocol with kind-specific methods.
@MainActor
protocol PaneRenderer: AnyObject {
    var view: NSView { get }
    func setFocused(_ focused: Bool)
}
