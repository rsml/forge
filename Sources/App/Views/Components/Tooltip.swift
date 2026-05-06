import SwiftUI

// MARK: - Tooltip Panel (floating NSPanel, pure AppKit rendering)

@MainActor
private final class TooltipPanel: NSPanel {
    static let shared = TooltipPanel()
    private weak var ownerWindow: NSWindow?
    private var generation = 0

    private let labelField: NSTextField
    private let hintField: NSTextField

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    private init() {
        labelField = NSTextField(labelWithString: "")
        labelField.font = .systemFont(ofSize: 12, weight: .medium)
        labelField.textColor = .white
        labelField.alignment = .center
        labelField.lineBreakMode = .byClipping

        hintField = NSTextField(labelWithString: "")
        hintField.font = .systemFont(ofSize: 11)
        hintField.textColor = .white.withAlphaComponent(0.7)
        hintField.alignment = .center
        hintField.lineBreakMode = .byClipping

        let pill = NSView()
        pill.wantsLayer = true
        pill.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.85).cgColor
        pill.layer?.cornerRadius = 6
        pill.layer?.shadowColor = NSColor.black.cgColor
        pill.layer?.shadowOpacity = 0.25
        pill.layer?.shadowRadius = 4
        pill.layer?.shadowOffset = CGSize(width: 0, height: -2)

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

        pill.addSubview(labelField)
        pill.addSubview(hintField)
        contentView = pill
    }

    func show(label: String, hint: String?, anchorScreenRect: CGRect, ownerWindow: NSWindow?) {
        generation += 1

        labelField.stringValue = label
        hintField.stringValue = hint ?? ""
        hintField.isHidden = hint == nil

        labelField.sizeToFit()
        if hint != nil { hintField.sizeToFit() }

        let hPad: CGFloat = 10, vPad: CGFloat = 6, spacing: CGFloat = 2
        let labelSize = labelField.frame.size
        let hintSize = hint != nil ? hintField.frame.size : .zero

        let innerW = max(labelSize.width, hintSize.width)
        let innerH = labelSize.height + (hint != nil ? spacing + hintSize.height : 0)
        let size = NSSize(width: ceil(innerW + hPad * 2), height: ceil(innerH + vPad * 2))

        // Layout (NSView origin is bottom-left)
        let hintY = vPad
        let labelY = vPad + (hint != nil ? hintSize.height + spacing : 0)
        labelField.frame = NSRect(
            x: hPad + (innerW - labelSize.width) / 2, y: labelY,
            width: labelSize.width, height: labelSize.height
        )
        if hint != nil {
            hintField.frame = NSRect(
                x: hPad + (innerW - hintSize.width) / 2, y: hintY,
                width: hintSize.width, height: hintSize.height
            )
        }

        setContentSize(size)

        let screen = NSScreen.screens.first(where: { $0.frame.contains(anchorScreenRect.origin) }) ?? NSScreen.main
        guard let visibleFrame = screen?.visibleFrame else { return }

        var x = anchorScreenRect.midX - size.width / 2
        var y = anchorScreenRect.minY - size.height - 4
        x = max(visibleFrame.minX + 4, min(x, visibleFrame.maxX - size.width - 4))
        if y < visibleFrame.minY + 4 {
            y = anchorScreenRect.maxY + 4
        }

        setFrameOrigin(NSPoint(x: x, y: y))
        alphaValue = 0

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
        let gen = generation
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.1
            self.animator().alphaValue = 0
        } completionHandler: { [weak self] in
            Task { @MainActor in
                guard let self, self.generation == gen else { return }
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
