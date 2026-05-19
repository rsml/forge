import AppKit

/// Terminal-specific rendering. Refines PaneRenderer with terminal IO concerns.
@MainActor
protocol TerminalRenderer: PaneRenderer {
    func feed(_ data: Data)
    func feedScrollback(_ content: String)
    var onInput: ((Data) -> Void)? { get set }
    var onResize: ((Int, Int) -> Void)? { get set }
}
