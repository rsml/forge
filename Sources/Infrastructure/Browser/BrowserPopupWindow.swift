import AppKit
import WebKit

/// Forge-owned floating popup window for `window.open()` calls from browser panes.
///
/// Hosts its own WKWebView in a non-activating NSPanel so it floats above the main
/// window but doesn't steal key focus. Auto-closes when JS calls `window.close()`
/// (common in OAuth and login flows).
///
/// Lifetime: each instance retains itself via the static `active` array while the
/// panel is on-screen, then removes itself in `webViewDidClose` or on manual close.
@MainActor
final class BrowserPopupWindow: NSObject {
    private let panel: NSPanel
    private let webView: WKWebView

    /// Strong references to keep popups alive while their panels are visible.
    /// Without this, the popup would deallocate as soon as the spawning scope
    /// returned, taking the WKWebView and NSPanel with it.
    private static var active: [BrowserPopupWindow] = []

    init(url: URL, size: NSSize) {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()
        let wv = WKWebView(frame: NSRect(origin: .zero, size: size), configuration: config)
        wv.load(URLRequest(url: url))
        self.webView = wv

        let p = NSPanel(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.titled, .closable, .resizable, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        p.contentView = wv
        p.title = "Forge"
        p.isFloatingPanel = true
        p.center()
        self.panel = p

        super.init()
        wv.uiDelegate = self
    }

    /// Show the panel and register it in the active list so it stays alive.
    func show() {
        panel.makeKeyAndOrderFront(nil)
        BrowserPopupWindow.active.append(self)
    }
}

extension BrowserPopupWindow: WKUIDelegate {
    /// Fires when JS calls `window.close()`. Tears down the panel and releases
    /// the strong reference so the popup can deallocate.
    func webViewDidClose(_ webView: WKWebView) {
        panel.close()
        BrowserPopupWindow.active.removeAll { $0 === self }
    }
}
