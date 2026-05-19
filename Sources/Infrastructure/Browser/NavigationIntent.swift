import AppKit
import Foundation

/// What should happen when a web page tries to open a new window.
/// Translated from WKWebView UI/Navigation delegate callbacks by the renderer.
enum NavigationIntent {
    /// target="_blank" link with no size hints — replace current pane URL.
    case sameTabBlank(URL)
    /// window.open() with size hints — open a floating Forge-owned popup window.
    case popupWindow(URL, size: NSSize?)
    /// ⌘+click on any link — open a new browser pane (split right).
    case modifierNewPane(URL)
}
