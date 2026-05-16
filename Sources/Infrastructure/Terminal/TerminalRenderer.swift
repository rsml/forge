import AppKit

/// Swappable terminal rendering abstraction.
/// SwiftTerm today, libghostty later. Lives in Infrastructure (not Core)
/// because terminal rendering is not a domain concern.
@MainActor
protocol TerminalRenderer: AnyObject {
    var view: NSView { get }
    func feed(_ data: Data)
    func feedScrollback(_ content: String)
    func setFocused(_ focused: Bool)
    var onInput: ((Data) -> Void)? { get set }
    var onResize: ((Int, Int) -> Void)? { get set }
}
