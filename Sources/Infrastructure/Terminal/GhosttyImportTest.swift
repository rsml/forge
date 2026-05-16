import GhosttyKit

/// Smoke test: verifies GhosttyKit links and the C API is accessible.
/// Delete this file after integration is complete.
enum GhosttyImportTest {
    static func verify() {
        _ = ghostty_surface_config_new()
        ForgeLog.log("[ghostty] GhosttyKit import verified")
    }
}
