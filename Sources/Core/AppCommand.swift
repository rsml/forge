/// Every user-initiated action that crosses view boundaries.
/// Pure enum — no framework imports, lives in ForgeCore.
public enum AppCommand: Equatable, Sendable {
    // Modals
    case showProjectPicker
    case showTabSwitcher
    case showCommandPalette
    case showNotifications
    case dismissModal

    // Sidebar
    case toggleSidebar
    case collapseAll
    case expandAll

    // Rename (enters inline rename mode)
    case renameTab
    case renameProject

    // Mode
    case toggleMode

    // Tab movement
    case moveTabLeft
    case moveTabRight

    // Project movement
    case moveProjectBack
    case moveProjectForward

    // Notifications
    case toggleNotifications

    // Stack actions
    case stackDone
    case stackHide
    case stackMoveToBack
}
