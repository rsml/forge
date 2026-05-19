import AppKit
import SwiftUI
import ForgeCore

/// Centered floating sheet attached to a browser pane. Lets the user enter
/// a URL or pick a detected port from sibling terminal panes. Renders inside
/// the pane's ZStack so it doesn't block other panes or window chrome.
///
/// Auto-opened on browser-pane creation (split/convert). ⌘L re-opens. Esc cancels.
/// Enter submits — selects the highlighted suggestion if one is highlighted,
/// otherwise parses the input as URL/search.
struct BrowserURLPalette: View {
    /// Pre-fill value for the URL bar. Empty for a fresh palette, the current
    /// page URL when opened via ⌘L or URL strip click. The TextField is
    /// initialised from this once on appear so the user sees the live URL and
    /// can edit it in place (or paste over to replace).
    let initialInput: String
    let suggestions: [DetectedPort]
    let onSubmit: (URL) -> Void
    let onCancel: () -> Void

    @State private var input: String = ""
    /// -1 = text input wins; 0...n = a suggestion is selected.
    @State private var highlighted: Int = -1
    @FocusState private var inputFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            TextField("URL or search", text: $input)
                .textFieldStyle(.plain)
                .font(.system(size: 14))
                .focused($inputFocused)
                .onSubmit { submit() }
                .onChange(of: input) { highlighted = -1 }

            if !suggestions.isEmpty {
                Divider().opacity(0.3)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Suggestions")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.tertiary)
                        .padding(.leading, 8)
                        .padding(.bottom, 4)
                    ForEach(Array(suggestions.enumerated()), id: \.offset) { i, port in
                        suggestionRow(port: port, isHighlighted: i == highlighted)
                            .onTapGesture { onSubmit(url(for: port)) }
                            .onHover { hovering in
                                if hovering { highlighted = i }
                            }
                    }
                }
            }
        }
        .padding(14)
        .frame(width: 480)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(Color.white.opacity(0.1), lineWidth: 0.5)
        )
        .shadow(radius: 24, y: 8)
        .onAppear {
            // Pre-fill with the current page URL (if any). The user can then
            // either edit in place, hit ⌘A to replace, or just start typing
            // after the post-focus select-all below.
            input = initialInput

            // Clear any existing first responder (commonly the WKWebView in a
            // loaded browser pane) so the .task loop has a clean slate.
            if let window = NSApp.keyWindow ?? NSApp.mainWindow {
                window.makeFirstResponder(nil)
            }
        }
        .task {
            // Repeatedly assert focus for the first 1s to combat first-responder
            // thieves — especially the freshly-created WKWebView when a split-as-
            // browser dispatches `makeFirstResponder(renderer.view)` AFTER this
            // palette's onAppear runs. At each tick, if the current first responder
            // is a WebView, force it to resign so SwiftUI's @FocusState rebind to
            // the TextField actually sticks.
            for i in 0..<10 {
                try? await Task.sleep(nanoseconds: 100_000_000)  // 100ms
                if let window = NSApp.keyWindow {
                    let fr = window.firstResponder
                    if String(describing: type(of: fr ?? NSObject())).contains("WebView") {
                        window.makeFirstResponder(nil)
                    }
                }
                inputFocused = true
                // Select-all on the third assert (~300ms in) so typing replaces
                // the pre-filled URL. SwiftUI TextField has no public selection
                // API on macOS — send the standard responder-chain selector.
                if i == 2 && !initialInput.isEmpty {
                    NSApp.sendAction(#selector(NSText.selectAll(_:)), to: nil, from: nil)
                }
            }
        }
        .onKeyPress(.escape) { onCancel(); return .handled }
        .onKeyPress(.upArrow) { handleUp(); return .handled }
        .onKeyPress(.downArrow) { handleDown(); return .handled }
    }

    private func suggestionRow(port: DetectedPort, isHighlighted: Bool) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "network")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            // `Text("\(...)")` treats the literal as a LocalizedStringKey and
            // applies en-US grouping to interpolated Ints — port 3000 prints
            // as "3,000". `Text(verbatim:)` bypasses localisation so the port
            // renders as digits only.
            Text(verbatim: "\(port.host):\(port.port)")
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(.primary)
            Spacer()
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(isHighlighted ? Color.accentColor.opacity(0.2) : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 4))
        .contentShape(Rectangle())
    }

    // MARK: - Keyboard navigation

    private func handleUp() {
        if suggestions.isEmpty { return }
        if highlighted <= 0 { highlighted = suggestions.count - 1 }
        else { highlighted -= 1 }
    }

    private func handleDown() {
        if suggestions.isEmpty { return }
        if highlighted >= suggestions.count - 1 { highlighted = 0 }
        else { highlighted += 1 }
    }

    private func submit() {
        if highlighted >= 0 && highlighted < suggestions.count {
            onSubmit(url(for: suggestions[highlighted]))
            return
        }
        if let parsed = parseInput(input) { onSubmit(parsed) }
        // Empty input + no selection → do nothing (per spec).
    }

    // MARK: - URL parsing

    private func url(for port: DetectedPort) -> URL {
        // PortDetector only emits known dev hosts + valid ports, so this never fails.
        URL(string: "http://\(port.host):\(port.port)")!
    }

    /// Recognised URL schemes. `URL(string:)` happily accepts anything before
    /// the colon as a scheme (including `localhost`), so a whitelist is
    /// required to avoid treating `localhost:3000` as a `localhost://3000` URL
    /// and dumping the user into DuckDuckGo.
    private static let knownSchemes: Set<String> = ["http", "https", "file", "about", "ftp"]

    private func parseInput(_ s: String) -> URL? {
        let trimmed = s.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty { return nil }

        // Already-qualified URL with a known web scheme.
        if let u = URL(string: trimmed),
           let scheme = u.scheme?.lowercased(),
           Self.knownSchemes.contains(scheme) {
            return u
        }

        // `host:port` or bare hostname — prepend `http://`. Use HTTP (not
        // HTTPS) because the common case is a local dev server, which rarely
        // serves HTTPS. The browser can still upgrade externally-resolved
        // hosts via HSTS.
        if let u = URL(string: "http://\(trimmed)"), u.host != nil {
            return u
        }

        // Fallback: search via DuckDuckGo.
        if let q = trimmed.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) {
            return URL(string: "https://duckduckgo.com/?q=\(q)")
        }
        return nil
    }
}
