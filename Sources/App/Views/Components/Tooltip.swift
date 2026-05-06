import SwiftUI

// MARK: - Tooltip Content

private struct TooltipContent: View {
    let label: String
    let hint: String?

    var body: some View {
        VStack(spacing: 2) {
            Text(label)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.white)
            if let hint {
                Text(hint)
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.7))
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color.black.opacity(0.85))
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .shadow(color: .black.opacity(0.25), radius: 4, y: 2)
    }
}

// MARK: - Tooltip Panel (floating NSPanel, never clipped)

@MainActor
private final class TooltipPanel: NSPanel {
    static let shared = TooltipPanel()
    private weak var ownerWindow: NSWindow?

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    private init() {
        super.init(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )
        isOpaque = false
        backgroundColor = .clear
        level = .floating
        hasShadow = false
        ignoresMouseEvents = true
        animationBehavior = .none
    }

    func show(label: String, hint: String?, anchorScreenRect: CGRect, ownerWindow: NSWindow?) {
        let hosting = NSHostingView(rootView: TooltipContent(label: label, hint: hint))
        let size = hosting.fittingSize

        contentView = hosting
        setContentSize(size)

        let screen = NSScreen.screens.first(where: { $0.frame.contains(anchorScreenRect.origin) }) ?? NSScreen.main
        guard let visibleFrame = screen?.visibleFrame else { return }

        // Center horizontally below anchor (screen coords are bottom-up)
        var x = anchorScreenRect.midX - size.width / 2
        var y = anchorScreenRect.minY - size.height - 4

        // Clamp horizontal
        x = max(visibleFrame.minX + 4, min(x, visibleFrame.maxX - size.width - 4))

        // If below screen bottom, show above instead
        if y < visibleFrame.minY + 4 {
            y = anchorScreenRect.maxY + 4
        }

        setFrameOrigin(NSPoint(x: x, y: y))
        alphaValue = 0

        // Attach as child so tooltip moves with the window
        if let ownerWindow, self.parent != ownerWindow {
            self.ownerWindow?.removeChildWindow(self)
            ownerWindow.addChildWindow(self, ordered: .above)
        }
        self.ownerWindow = ownerWindow

        orderFront(nil)
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.15
            self.animator().alphaValue = 1
        }
    }

    func hideTooltip() {
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.1
            self.animator().alphaValue = 0
        } completionHandler: { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                self.ownerWindow?.removeChildWindow(self)
                self.ownerWindow = nil
                self.orderOut(nil)
            }
        }
    }
}

// MARK: - Anchor (NSView bridge to get screen coordinates)

private final class TooltipAnchorView: NSView {}

private struct TooltipAnchor: NSViewRepresentable {
    let anchorView: TooltipAnchorView
    func makeNSView(context: Context) -> TooltipAnchorView { anchorView }
    func updateNSView(_ nsView: TooltipAnchorView, context: Context) {}
}

// MARK: - Modifier

private struct TooltipModifier: ViewModifier {
    let label: String
    let hint: String?
    let delay: TimeInterval

    @State private var anchorView = TooltipAnchorView()
    @State private var showTask: Task<Void, Never>?

    func body(content: Content) -> some View {
        content
            .background(TooltipAnchor(anchorView: anchorView))
            .onHover { hovering in
                if hovering {
                    showTask = Task { @MainActor in
                        try? await Task.sleep(for: .seconds(delay))
                        guard !Task.isCancelled else { return }
                        guard let window = anchorView.window else { return }
                        let windowRect = anchorView.convert(anchorView.bounds, to: nil)
                        let screenRect = window.convertToScreen(windowRect)
                        TooltipPanel.shared.show(
                            label: label, hint: hint,
                            anchorScreenRect: screenRect,
                            ownerWindow: window
                        )
                    }
                } else {
                    showTask?.cancel()
                    showTask = nil
                    TooltipPanel.shared.hideTooltip()
                }
            }
            .onDisappear {
                showTask?.cancel()
                showTask = nil
                TooltipPanel.shared.hideTooltip()
            }
    }
}

// MARK: - View Extensions

extension View {
    func tooltip(_ text: String?) -> some View {
        if let text, !text.isEmpty {
            return AnyView(modifier(TooltipModifier(label: text, hint: nil, delay: 0.5)))
        }
        return AnyView(self)
    }

    func tooltip(_ shortcut: Shortcut) -> some View {
        modifier(TooltipModifier(label: shortcut.label, hint: shortcut.hint, delay: 0.5))
    }
}
