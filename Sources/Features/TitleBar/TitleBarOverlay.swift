import AppKit

/// Extension handling overlay installation and chrome stripping — the AppKit layout code.
extension TitleBarManager {

    // MARK: - Chrome Stripping

    func stripTitleBarChrome() {
        guard let themeFrame = window.contentView?.superview else { return }
        Self.hideTitleBarChrome(in: themeFrame)
        applyTitleBarBackground()
    }

    private static func hideTitleBarChrome(in view: NSView) {
        let name = String(describing: type(of: view))
        if name == "NSTitlebarContainerView" {
            for child in view.subviews {
                let childName = String(describing: type(of: child))
                if childName == "_NSTitlebarDecorationView" || child is NSVisualEffectView {
                    child.isHidden = true
                }
            }
            return
        }
        for sub in view.subviews {
            hideTitleBarChrome(in: sub)
        }
    }

    static func findView(named name: String, in view: NSView) -> NSView? {
        if String(describing: type(of: view)) == name { return view }
        for sub in view.subviews {
            if let found = findView(named: name, in: sub) { return found }
        }
        return nil
    }

    func applyTitleBarBackground() {
        guard let themeFrame = window.contentView?.superview,
              let titlebarView = Self.findView(named: "NSTitlebarView", in: themeFrame)
        else { return }

        let color: NSColor
        if let theme = config.resolvedTheme {
            color = NSColor(theme.background.color)
                .blended(withFraction: 0.06, of: NSColor.white) ?? NSColor(theme.background.color)
        } else {
            color = NSColor(red: 0.1, green: 0.1, blue: 0.1, alpha: 1)
        }

        titlebarView.wantsLayer = true
        titlebarView.layer?.backgroundColor = color.cgColor

        if let bgView = Self.findView(named: "NSTitlebarBackgroundView", in: titlebarView) {
            bgView.wantsLayer = true
            bgView.layer?.backgroundColor = color.cgColor
        }
    }

    // MARK: - Overlay Installation

    func installTitleBarOverlay() {
        guard let themeFrame = window.contentView?.superview,
              let container = Self.findView(named: "NSTitlebarContainerView", in: themeFrame)
        else { return }

        titleBarOverlay?.removeFromSuperview()

        let overlay = NSView()
        overlay.wantsLayer = true
        overlay.translatesAutoresizingMaskIntoConstraints = false

        let titleFont = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize, weight: .regular)

        let pathLabel = NSTextField(labelWithString: "")
        pathLabel.font = titleFont
        pathLabel.textColor = .secondaryLabelColor
        pathLabel.lineBreakMode = .byTruncatingMiddle
        pathLabel.translatesAutoresizingMaskIntoConstraints = false
        pathLabel.identifier = NSUserInterfaceItemIdentifier("titlePath")

        let branchLabel = NSTextField(labelWithString: "")
        branchLabel.font = titleFont
        branchLabel.textColor = .secondaryLabelColor
        branchLabel.lineBreakMode = .byTruncatingTail
        branchLabel.translatesAutoresizingMaskIntoConstraints = false
        branchLabel.identifier = NSUserInterfaceItemIdentifier("titleBranch")

        let splitH = NSButton(image: NSImage(systemSymbolName: "rectangle.split.2x1", accessibilityDescription: "Split Horizontally")!, target: self, action: #selector(splitHorizontalAction))
        splitH.isBordered = false
        splitH.bezelStyle = .accessoryBarAction
        splitH.contentTintColor = .secondaryLabelColor
        splitH.imageScaling = .scaleProportionallyDown
        splitH.setForgeTooltip(KeyboardShortcuts.splitHorizontal, hoverTint: true)
        splitH.translatesAutoresizingMaskIntoConstraints = false

        let splitV = NSButton(image: NSImage(systemSymbolName: "rectangle.split.1x2", accessibilityDescription: "Split Vertically")!, target: self, action: #selector(splitVerticalAction))
        splitV.isBordered = false
        splitV.bezelStyle = .accessoryBarAction
        splitV.contentTintColor = .secondaryLabelColor
        splitV.imageScaling = .scaleProportionallyDown
        splitV.setForgeTooltip(KeyboardShortcuts.splitVertical, hoverTint: true)
        splitV.translatesAutoresizingMaskIntoConstraints = false

        splitHButton = splitH
        splitVButton = splitV

        overlay.addSubview(pathLabel)
        overlay.addSubview(branchLabel)
        overlay.addSubview(splitH)
        overlay.addSubview(splitV)

        pathLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        branchLabel.setContentCompressionResistancePriority(.required, for: .horizontal)

        let pathLeading = pathLabel.leadingAnchor.constraint(equalTo: overlay.leadingAnchor, constant: 78)
        pathLabelLeadingConstraint = pathLeading

        let branchToOverlay = branchLabel.trailingAnchor.constraint(equalTo: overlay.trailingAnchor, constant: -12)
        let branchToSplitH = branchLabel.trailingAnchor.constraint(lessThanOrEqualTo: splitH.leadingAnchor, constant: -8)
        branchTrailingToOverlay = branchToOverlay
        branchTrailingToSplitH = branchToSplitH

        NSLayoutConstraint.activate([
            pathLeading,
            pathLabel.centerYAnchor.constraint(equalTo: overlay.centerYAnchor),
            branchLabel.centerYAnchor.constraint(equalTo: overlay.centerYAnchor),
            pathLabel.trailingAnchor.constraint(lessThanOrEqualTo: branchLabel.leadingAnchor, constant: -8),

            splitH.widthAnchor.constraint(equalToConstant: 20),
            splitH.heightAnchor.constraint(equalToConstant: 20),
            splitH.centerYAnchor.constraint(equalTo: overlay.centerYAnchor),

            splitV.leadingAnchor.constraint(equalTo: splitH.trailingAnchor, constant: 2),
            splitV.widthAnchor.constraint(equalToConstant: 20),
            splitV.heightAnchor.constraint(equalToConstant: 20),
            splitV.centerYAnchor.constraint(equalTo: overlay.centerYAnchor),
            splitV.trailingAnchor.constraint(equalTo: overlay.trailingAnchor, constant: -12),
        ])

        container.addSubview(overlay)
        let leading = overlay.leadingAnchor.constraint(equalTo: container.leadingAnchor)
        let trailing = overlay.trailingAnchor.constraint(equalTo: container.trailingAnchor)
        overlayLeadingConstraint = leading
        overlayTrailingConstraint = trailing

        NSLayoutConstraint.activate([
            leading,
            trailing,
            overlay.topAnchor.constraint(equalTo: container.topAnchor),
            overlay.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])

        titleBarOverlay = overlay

        // Mode toggle button — added to container (not overlay) so it can appear over the sidebar area
        modeToggleButton?.removeFromSuperview()
        let modeBtn = NSButton(image: NSImage(systemSymbolName: "rectangle.stack", accessibilityDescription: "Switch to Stack Mode")!, target: self, action: #selector(toggleModeAction))
        modeBtn.wantsLayer = true
        modeBtn.isBordered = false
        modeBtn.bezelStyle = .accessoryBarAction
        modeBtn.contentTintColor = .secondaryLabelColor
        modeBtn.imageScaling = .scaleProportionallyDown
        modeBtn.setForgeTooltip("Toggle Mode", hint: KeyboardShortcuts.toggleMode.hint, hoverTint: true)
        modeBtn.translatesAutoresizingMaskIntoConstraints = false
        modeToggleButton = modeBtn

        container.addSubview(modeBtn)
        let modeBtnLeading = modeBtn.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 82)
        modeButtonLeadingConstraint = modeBtnLeading
        NSLayoutConstraint.activate([
            modeBtnLeading,
            modeBtn.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            modeBtn.widthAnchor.constraint(equalToConstant: 28),
            modeBtn.heightAnchor.constraint(equalToConstant: 28),
        ])

        updateOverlayConstraints()
        updateSplitIconVisibility()
    }
}
