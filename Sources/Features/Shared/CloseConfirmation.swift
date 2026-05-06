import AppKit
import ForgeCore

/// NSAlert presentation for close confirmation decisions.
extension CloseConfirmation {

    /// Show an NSAlert for the given info. Returns true if user confirmed.
    @MainActor
    static func present(_ info: AlertInfo) -> Bool {
        let alert = NSAlert()
        alert.messageText = info.message
        alert.informativeText = info.info
        alert.addButton(withTitle: info.action)
        alert.addButton(withTitle: "Cancel")
        alert.alertStyle = .warning
        return alert.runModal() == .alertFirstButtonReturn
    }
}
