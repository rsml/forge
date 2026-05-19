import SwiftUI
import ForgeCore

/// Floating find-in-page bar overlaid at the top of a browser pane. Wired to
/// `BrowserRenderer.find(_:forward:)` — types-to-search updates highlights live,
/// arrows step matches, Esc dismisses (also clears highlights via `dismissFind`).
struct BrowserFindBar: View {
    let pane: Pane
    let renderer: any BrowserRenderer
    let onDismiss: () -> Void

    @State private var query: String = ""
    @State private var lastMatchFound: Bool = true
    @FocusState private var inputFocused: Bool

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)

            TextField("Find in page", text: $query)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .focused($inputFocused)
                .onChange(of: query) { _, _ in
                    runFind(forward: true)
                }
                .onSubmit {
                    runFind(forward: true)
                }
                .onKeyPress(.escape) {
                    dismiss()
                    return .handled
                }

            if !lastMatchFound && !query.isEmpty {
                Text("Not found")
                    .font(.system(size: 11))
                    .foregroundStyle(.red.opacity(0.8))
            }

            Button {
                runFind(forward: false)
            } label: {
                Image(systemName: "chevron.up").font(.system(size: 11))
            }
            .buttonStyle(.borderless)
            .disabled(query.isEmpty)

            Button {
                runFind(forward: true)
            } label: {
                Image(systemName: "chevron.down").font(.system(size: 11))
            }
            .buttonStyle(.borderless)
            .disabled(query.isEmpty)

            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark").font(.system(size: 10))
            }
            .buttonStyle(.borderless)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .frame(width: 320)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(Color.white.opacity(0.1), lineWidth: 0.5)
        )
        .shadow(radius: 8, y: 2)
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                inputFocused = true
            }
        }
    }

    private func runFind(forward: Bool) {
        guard !query.isEmpty else {
            lastMatchFound = true
            return
        }
        Task {
            let found = await renderer.find(query, forward: forward)
            lastMatchFound = found
        }
    }

    private func dismiss() {
        renderer.dismissFind()
        onDismiss()
    }
}
