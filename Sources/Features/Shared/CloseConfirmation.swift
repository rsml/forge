import AppKit
import ForgeCore

/// NSAlert presentation for close confirmation decisions.
extension CloseConfirmation {

    /// Show an NSAlert as a window sheet for the given info. Returns true if user confirmed.
    ///
    /// Apple HIG: the destructive action is styled red (`hasDestructiveAction`) and Cancel is
    /// the default button (Enter cancels), so an unintended Enter keypress does not destroy work.
    @MainActor
    static func present(_ info: AlertInfo, in window: NSWindow) async -> Bool {
        await withCheckedContinuation { (cont: CheckedContinuation<Bool, Never>) in
            let alert = NSAlert()
            alert.messageText = info.message
            alert.informativeText = info.info
            alert.alertStyle = .warning

            let destructive = alert.addButton(withTitle: info.action)
            destructive.hasDestructiveAction = true
            destructive.keyEquivalent = ""  // unbind Enter from destructive

            let cancel = alert.addButton(withTitle: "Cancel")
            cancel.keyEquivalent = "\r"     // Enter = Cancel

            alert.beginSheetModal(for: window) { response in
                cont.resume(returning: response == .alertFirstButtonReturn)
            }
        }
    }
}
