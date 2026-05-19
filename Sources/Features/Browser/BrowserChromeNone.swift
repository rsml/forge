import SwiftUI
import AppKit

/// Chromeless browser pane — just the WKWebView NSView, no chrome.
/// Mode A (Full) and B (Slim) come in Task 13.
///
/// Wraps the WKWebView host in a white SwiftUI background so the pane
/// shows white (not the dark theme background) before the page paints.
/// WKWebView is transparent until the first frame renders, so without this
/// the pane flashes dark on creation and "snaps to white" on first interaction.
struct BrowserChromeNone: View {
    let renderer: any BrowserRenderer

    var body: some View {
        Color.white
            .overlay(BrowserWebViewHost(renderer: renderer))
    }
}

private struct BrowserWebViewHost: NSViewRepresentable {
    let renderer: any BrowserRenderer

    func makeNSView(context: Context) -> NSView { renderer.view }
    func updateNSView(_ nsView: NSView, context: Context) {}
}
