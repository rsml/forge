import AppKit
import WebKit
import Foundation

/// WKWebView subclass that reports first-responder focus changes through a
/// callback. Lets the renderer (and ultimately WorkspaceController) know which
/// browser pane the user just clicked into so ⌘L / ⌘F can target it.
///
/// Also forces a white layer background so the pane doesn't flash the dark
/// theme color before the first page paint — WKWebView itself is transparent
/// until the document renders content.
final class FocusReportingWebView: WKWebView {
    var onFocusGained: (() -> Void)?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        wantsLayer = true
        layer?.backgroundColor = NSColor.white.cgColor
    }

    override func becomeFirstResponder() -> Bool {
        let became = super.becomeFirstResponder()
        if became { onFocusGained?() }
        return became
    }
}

/// Concrete BrowserRenderer backed by WKWebView.
/// Lives in Infrastructure/Browser/ alongside the protocol it conforms to.
@MainActor
final class WebKitBrowserRenderer: NSObject, BrowserRenderer {

    // MARK: - PaneRenderer

    let view: NSView

    // MARK: - BrowserRenderer state

    private let webView: FocusReportingWebView
    private var observers: [NSKeyValueObservation] = []

    var url: URL? { webView.url }

    // MARK: - Callbacks

    var onURLChange: ((URL) -> Void)?
    var onTitleChange: ((String) -> Void)?
    var onLoadingChange: ((Bool) -> Void)?
    var onProgress: ((Double) -> Void)?
    // TODO: onFaviconChange is currently never invoked. WKWebView has no built-in
    // favicon KVO. A future task should either inject JS to watch <link rel="icon">
    // or fetch /favicon.ico on didFinishNavigation. Tracked for post-v1.
    var onFaviconChange: ((Data?) -> Void)?
    var onNavigationRequest: ((NavigationIntent) -> Void)?
    var onLoadError: ((Error) -> Void)?
    var onCanGoBackChange: ((Bool) -> Void)?
    var onCanGoForwardChange: ((Bool) -> Void)?
    var onFocusGained: (() -> Void)?

    // MARK: - Init

    override init() {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()
        // Legacy private path — enables developer extras (Inspect Element menu
        // item, JavaScript console, etc.) on older macOS. Modern macOS uses
        // `isInspectable` (set below).
        config.preferences.setValue(true, forKey: "developerExtrasEnabled")
        let wv = FocusReportingWebView(frame: .zero, configuration: config)
        wv.allowsBackForwardNavigationGestures = true
        // macOS 13.3+ requires `isInspectable = true` for Web Inspector access.
        // Without this, right-click → Inspect Element is absent and the private
        // `_inspector.show:` selector silently fails. This is the public, supported
        // API since iOS 16.4 / macOS 13.3.
        if #available(macOS 13.3, *) {
            wv.isInspectable = true
        }
        // Paint white instead of flashing the theme color before first paint.
        // WKWebView is transparent until the document renders content. Three
        // layered defenses:
        //   1. underPageBackgroundColor — shows where the loaded page is
        //      transparent (macOS 12+).
        //   2. Private "drawsBackground" key — disables WKWebView's own
        //      transparent background and lets the layer color win.
        //   3. wantsLayer + layer backgroundColor — guarantees a white pixel
        //      under every region of the view, including before any page loads.
        wv.underPageBackgroundColor = .white
        wv.setValue(false, forKey: "drawsBackground")
        wv.wantsLayer = true
        wv.layer?.backgroundColor = NSColor.white.cgColor
        self.webView = wv
        self.view = wv
        super.init()
        wv.navigationDelegate = self
        wv.uiDelegate = self
        wv.onFocusGained = { [weak self] in self?.onFocusGained?() }
        installObservers()
    }

    deinit {
        // KVO observations clean up automatically via NSKeyValueObservation's deinit.
    }

    private func installObservers() {
        observers.append(webView.observe(\.url, options: [.new]) { [weak self] wv, _ in
            if let u = wv.url { self?.onURLChange?(u) }
        })
        observers.append(webView.observe(\.title, options: [.new]) { [weak self] wv, _ in
            self?.onTitleChange?(wv.title ?? "")
        })
        observers.append(webView.observe(\.isLoading, options: [.new]) { [weak self] wv, _ in
            self?.onLoadingChange?(wv.isLoading)
        })
        observers.append(webView.observe(\.estimatedProgress, options: [.new]) { [weak self] wv, _ in
            self?.onProgress?(wv.estimatedProgress)
        })
        observers.append(webView.observe(\.canGoBack, options: [.new]) { [weak self] wv, _ in
            self?.onCanGoBackChange?(wv.canGoBack)
        })
        observers.append(webView.observe(\.canGoForward, options: [.new]) { [weak self] wv, _ in
            self?.onCanGoForwardChange?(wv.canGoForward)
        })
    }

    // MARK: - PaneRenderer methods

    func setFocused(_ focused: Bool) {
        if focused { view.window?.makeFirstResponder(webView) }
    }

    // MARK: - BrowserRenderer methods

    func loadURL(_ url: URL) {
        webView.load(URLRequest(url: url))
    }

    func goBack() { webView.goBack() }
    func goForward() { webView.goForward() }
    func reload() { webView.reload() }

    func find(_ query: String, forward: Bool) async -> Bool {
        let config = WKFindConfiguration()
        config.backwards = !forward
        return await withCheckedContinuation { cont in
            webView.find(query, configuration: config) { result in
                cont.resume(returning: result.matchFound)
            }
        }
    }

    func dismissFind() {
        // WKWebView has no public "clear find highlights" API.
        // Calling find with an empty string clears the active result UI on most macOS versions.
        let config = WKFindConfiguration()
        webView.find("", configuration: config) { _ in }
    }

    func setMuted(_ muted: Bool) {
        // Private but stable: matches WKWebView.isMuted KVO.
        webView.setValue(muted, forKey: "_muted")
    }

    func toggleDevTools() {
        // _WKInspector exposes `- (void)show;` and `- (void)hide;` — no colon,
        // no argument. Using `show:`/`hide:` silently no-ops.
        guard let inspector = webView.value(forKey: "_inspector") as? NSObject else {
            ForgeLog.log("[browser] _inspector unavailable; user can right-click → Inspect Element")
            return
        }
        let isVisible = (inspector.value(forKey: "isVisible") as? Bool) == true
        let sel = NSSelectorFromString(isVisible ? "hide" : "show")
        guard inspector.responds(to: sel) else {
            ForgeLog.log("[browser] _inspector does not respond to \(isVisible ? "hide" : "show"); user can right-click → Inspect Element")
            return
        }
        _ = inspector.perform(sel)
    }
}

// MARK: - WKNavigationDelegate

extension WebKitBrowserRenderer: WKNavigationDelegate {
    func webView(_ webView: WKWebView,
                 decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping @MainActor @Sendable (WKNavigationActionPolicy) -> Void) {
        // ⌘+click on a link → emit modifierNewPane intent, cancel default.
        // Filter on main-frame target rather than .linkActivated to catch JS-driven
        // navs and ⌘+click on <button> form submits, not just plain <a> links.
        let cmd = navigationAction.modifierFlags.contains(.command)
        if cmd,
           let url = navigationAction.request.url,
           navigationAction.targetFrame?.isMainFrame == true {
            onNavigationRequest?(.modifierNewPane(url))
            decisionHandler(.cancel)
            return
        }
        decisionHandler(.allow)
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        onLoadError?(error)
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        onLoadError?(error)
    }
}

// MARK: - WKUIDelegate

extension WebKitBrowserRenderer: WKUIDelegate {
    func webView(_ webView: WKWebView,
                 createWebViewWith configuration: WKWebViewConfiguration,
                 for navigationAction: WKNavigationAction,
                 windowFeatures: WKWindowFeatures) -> WKWebView? {
        guard let url = navigationAction.request.url else { return nil }

        // target="_blank" with no size hints → same pane
        if windowFeatures.width == nil && windowFeatures.height == nil {
            onNavigationRequest?(.sameTabBlank(url))
            return nil
        }

        // window.open() with explicit size → floating popup
        let w = windowFeatures.width?.doubleValue ?? 600
        let h = windowFeatures.height?.doubleValue ?? 700
        onNavigationRequest?(.popupWindow(url, size: NSSize(width: w, height: h)))
        return nil
    }
}
