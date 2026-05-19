import SwiftUI
import ForgeCore

/// Chrome mode A — Full. Persistent ~28px top bar with back, forward, reload,
/// URL field, and a menu glyph. Shows a 1px progress bar at the bottom edge
/// while loading.
struct BrowserChromeFull: View {
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
                IconButton(systemName: "chevron.left") { renderer.goBack() }
                    .frame(width: 22, height: 22)
                    .disabled(!(pane.browserState?.canGoBack ?? false))

                IconButton(systemName: "chevron.right") { renderer.goForward() }
                    .frame(width: 22, height: 22)
                    .disabled(!(pane.browserState?.canGoForward ?? false))

                IconButton(systemName: "arrow.clockwise") { renderer.reload() }
                    .frame(width: 22, height: 22)

                urlField

                BrowserChromeMenu(pane: pane, renderer: renderer)
                    .frame(width: 22, height: 22)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(Color.white.opacity(0.06))

            progressBar
        }
    }

    @ViewBuilder
    private var urlField: some View {
        Button {
            appState.openURLPalette(for: pane)
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "lock.fill")
                    .font(.system(size: 9))
                    .foregroundStyle(.green.opacity(0.7))
                Text(pane.browserState?.url?.absoluteString ?? "")
                    .font(.system(size: 11, design: .monospaced))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .foregroundStyle(.primary)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Color.black.opacity(0.25))
            .clipShape(RoundedRectangle(cornerRadius: 10))
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
