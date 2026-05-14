import AppKit
import SwiftTerm

/// SwiftTerm implementation of TerminalRenderer.
/// Uses the base `TerminalView` (not `LocalProcessTerminalView`) — no process needed.
/// `@preconcurrency` on `TerminalViewDelegate` silences the Swift 6 conformance-isolation
/// diagnostic: SwiftTerm's delegate protocol predates strict concurrency and is always
/// called on the main thread by AppKit, so this is safe.
@MainActor
final class SwiftTermRenderer: NSObject, TerminalRenderer, @preconcurrency TerminalViewDelegate {
    let terminalView: TerminalView
    var onInput: ((Data) -> Void)?
    var onResize: ((Int, Int) -> Void)?

    var view: NSView { terminalView }

    init(font: NSFont, foreground: NSColor, background: NSColor, colors: [SwiftTerm.Color]?) {
        terminalView = TerminalView(frame: .zero)
        super.init()
        terminalView.autoresizingMask = [.width, .height]
        terminalView.font = font
        terminalView.nativeForegroundColor = foreground
        terminalView.nativeBackgroundColor = background
        if let colors, colors.count == 16 {
            terminalView.installColors(colors)
        }
        terminalView.terminalDelegate = self
    }

    func feed(_ data: Data) {
        terminalView.feed(byteArray: ArraySlice([UInt8](data)))
    }

    func feedScrollback(_ content: String) {
        terminalView.feed(text: content)
    }

    func resize(cols: Int, rows: Int) {
        terminalView.resize(cols: cols, rows: rows)
    }

    // MARK: - TerminalViewDelegate

    func send(source: TerminalView, data: ArraySlice<UInt8>) {
        onInput?(Data(data))
    }

    func sizeChanged(source: TerminalView, newCols: Int, newRows: Int) {
        onResize?(newCols, newRows)
    }

    func setTerminalTitle(source: TerminalView, title: String) {}
    func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {}
    func scrolled(source: TerminalView, position: Double) {}
    func clipboardCopy(source: TerminalView, content: Data) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setData(content, forType: .string)
    }
    func rangeChanged(source: TerminalView, startY: Int, endY: Int) {}
    func requestOpenLink(source: TerminalView, link: String, params: [String: String]) {
        if let url = URL(string: link) { NSWorkspace.shared.open(url) }
    }
    func iTermContent(source: TerminalView, content: ArraySlice<UInt8>) {}
    func bell(source: TerminalView) {}
}
