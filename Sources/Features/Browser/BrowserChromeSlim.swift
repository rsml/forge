import SwiftUI
import ForgeCore

/// Chrome mode B — Slim. Single-line ~18px strip showing the host and page
/// title, with reload + menu glyphs on the right. No back/forward buttons —
/// use the keyboard shortcuts (⌘[ / ⌘]). Shows a 1px progress bar at the
/// bottom edge while loading.
struct BrowserChromeSlim: View {
    @Environment(AppState.self) private var appState

    let pane: Pane
    let renderer: any BrowserRenderer

    var body: some View {
        VStack(spacing: 0) {
            chromeBar
            BrowserChromeNone(renderer: renderer)
        }
    }

    @ViewBuilder
    private var chromeBar: some View {
        ZStack(alignment: .bottom) {
            HStack(spacing: 6) {
                urlStrip

                IconButton(systemName: "arrow.clockwise") { renderer.reload() }
                    .frame(width: 18, height: 14)

                BrowserChromeMenu(pane: pane, renderer: renderer)
                    .frame(width: 18, height: 14)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Color.white.opacity(0.04))

            progressBar
        }
    }

    @ViewBuilder
    private var urlStrip: some View {
        Button {
            appState.openURLPalette(for: pane)
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "lock.fill")
                    .font(.system(size: 8))
                    .foregroundStyle(.green.opacity(0.7))

                Text(pane.browserState?.url?.host() ?? "")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.primary)

                if !(pane.browserState?.pageTitle.isEmpty ?? true) {
                    Text("·")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)

                    Text(pane.browserState?.pageTitle ?? "")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }

                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var progressBar: some View {
        if pane.browserState?.isLoading == true {
            GeometryReader { geo in
                Rectangle()
                    .fill(Color.accentColor)
                    .frame(width: geo.size.width * (pane.browserState?.loadingProgress ?? 0),
                           height: 1)
                    .animation(.linear(duration: 0.15),
                               value: pane.browserState?.loadingProgress)
            }
            .frame(height: 1)
        }
    }
}
