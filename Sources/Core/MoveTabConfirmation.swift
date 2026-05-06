/// Determines whether a move-tab operation requires user confirmation.
/// Pure decision logic — no framework imports.
public enum MoveTabConfirmation {

    public struct AlertInfo {
        public let message: String
        public let info: String
        public let action: String
        public let suppressionLabel: String

        public init(message: String, info: String, action: String, suppressionLabel: String) {
            self.message = message
            self.info = info
            self.action = action
            self.suppressionLabel = suppressionLabel
        }
    }

    /// Returns alert info when confirmation is needed, nil when the move should proceed silently.
    public static func evaluate(
        tabName: String, sourceProjectName: String, targetProjectName: String,
        warnOnMoveTab: Bool
    ) -> AlertInfo? {
        guard warnOnMoveTab else { return nil }
        return AlertInfo(
            message: "Move tab to \"\(targetProjectName)\"?",
            info: "\"\(tabName)\" will be moved from \"\(sourceProjectName)\".",
            action: "Move Tab",
            suppressionLabel: "Don't ask again"
        )
    }
}
