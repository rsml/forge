import AppKit
import Foundation

/// Browser-specific rendering. Refines PaneRenderer with WebKit-style navigation.
/// Concrete adapter: WebKitBrowserRenderer (Task 6).
@MainActor
protocol BrowserRenderer: PaneRenderer {
    /// Current URL displayed in the renderer; nil until first navigation completes.
    var url: URL? { get }

    /// Begin loading `url`. Replaces current page in this renderer.
    func loadURL(_ url: URL)

    /// Browser history navigation.
    func goBack()
    func goForward()
    func reload()

    /// Search current page for `query`, stepping in the given direction.
    /// Returns true if a match was found.
    func find(_ query: String, forward: Bool) async -> Bool

    /// Clear all find highlights and dismiss the find session.
    func dismissFind()

    /// Toggle the WKWebView floating inspector (⌘⌥I).
    func toggleDevTools()

    /// Mute audio playback for this renderer (true when pane not in active tab/project).
    func setMuted(_ muted: Bool)

    // MARK: - Observation callbacks

    /// Fires whenever the URL changes (user nav, redirect, JS history pushState).
    var onURLChange: ((URL) -> Void)? { get set }

    /// Fires whenever the document.title changes.
    var onTitleChange: ((String) -> Void)? { get set }

    /// Fires only when isLoading transitions (start of load, end of load).
    var onLoadingChange: ((Bool) -> Void)? { get set }

    /// Fires on every estimatedProgress KVO event (0.0...1.0). May fire many times per load.
    var onProgress: ((Double) -> Void)? { get set }

    /// Raw favicon bytes (PNG/JPEG). nil clears.
    var onFaviconChange: ((Data?) -> Void)? { get set }

    /// Fires when WKWebView requests a new window (target=_blank, window.open(), ⌘+click).
    /// Owner (WorkspaceController) decides how to satisfy the intent.
    var onNavigationRequest: ((NavigationIntent) -> Void)? { get set }

    /// Fires when navigation fails (DNS error, SSL error, network, etc.).
    var onLoadError: ((Error) -> Void)? { get set }

    /// Fires when WKWebView's history-back capability changes.
    var onCanGoBackChange: ((Bool) -> Void)? { get set }

    /// Fires when WKWebView's history-forward capability changes.
    var onCanGoForwardChange: ((Bool) -> Void)? { get set }

    /// Fires when the WKWebView gains first-responder focus (user clicked into the page).
    var onFocusGained: (() -> Void)? { get set }
}
