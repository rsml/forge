@preconcurrency import AppKit
import GhosttyKit

/// Manages the ghostty app lifecycle: init, config, wakeup/tick coalescing, focus tracking.
/// Created at the composition root (AppDelegate) and injected where needed.
@MainActor
final class GhosttyApp {
    // nonisolated(unsafe): these are opaque pointers freed in deinit, which
    // is nonisolated in Swift 6. Only mutated on MainActor during init.
    nonisolated(unsafe) private(set) var app: ghostty_app_t?
    nonisolated(unsafe) private(set) var config: ghostty_config_t?

    // Wakeup coalescing: the I/O thread may fire wakeup_cb hundreds of times
    // per second. We only need one pending tick on the main queue at a time.
    // Both fields are accessed from the I/O thread (handleWakeup) and main
    // thread (tick), protected by tickLock. nonisolated(unsafe) is required
    // because Swift concurrency cannot see the lock-based synchronization.
    nonisolated(unsafe) private var tickScheduled = false
    private let tickLock = NSLock()

    // Action callbacks — set by callers who need to observe Ghostty events.
    var onBell: ((ghostty_surface_t?) -> Void)?
    var onSetTitle: ((ghostty_surface_t?, String) -> Void)?
    var onCellSize: ((ghostty_surface_t?, UInt32, UInt32) -> Void)?
    var onChildExited: ((ghostty_surface_t?) -> Void)?
    var onCommandFinished: ((ghostty_surface_t?) -> Void)?
    var onPwd: ((ghostty_surface_t?, String) -> Void)?

    nonisolated(unsafe) private var focusObservers: [NSObjectProtocol] = []

    init() {
        guard initialize() else { return }
        subscribeFocusNotifications()
    }

    deinit {
        for observer in focusObservers {
            NotificationCenter.default.removeObserver(observer)
        }
        // Caller must free all surfaces BEFORE this deinit runs.
        if let app { ghostty_app_free(app) }
        if let config { ghostty_config_free(config) }
    }

    // MARK: - Config Update

    /// Applies font and color overrides from Forge config.
    func applyConfig(
        fontFamily: String?, fontSize: Int,
        foreground: String?, background: String?,
        ansiColors: [String]? = nil
    ) {
        guard let app else { return }

        guard let newConfig = ghostty_config_new() else {
            ForgeLog.log("[ghostty] failed to create config for applyConfig")
            return
        }

        var lines: [String] = [
            "window-padding-x=0",
            "window-padding-y=0",
            "window-padding-balance=false",
        ]
        if let family = fontFamily {
            lines.append("font-family=\(family)")
        }
        lines.append("font-size=\(fontSize)")
        if let fg = foreground {
            lines.append("foreground=\(fg)")
        }
        if let bg = background {
            lines.append("background=\(bg)")
        }
        // Ghostty palette config: palette=N=#RRGGBB
        if let colors = ansiColors {
            for (i, hex) in colors.prefix(16).enumerated() {
                lines.append("palette=\(i)=\(hex)")
            }
        }

        let configString = lines.joined(separator: "\n")
        loadConfigString(configString, into: newConfig, label: "applyConfig")
        ghostty_config_finalize(newConfig)
        ghostty_app_update_config(app, newConfig)
        // ghostty takes ownership of the config via update; do NOT free it.
    }

    // MARK: - Wakeup (called from I/O thread)

    /// Called from ghostty's I/O thread. Must be nonisolated because
    /// it runs off the main actor. Uses lock-based coalescing to avoid
    /// flooding the main thread with ticks.
    nonisolated func handleWakeup() {
        tickLock.lock()
        defer { tickLock.unlock() }
        guard !tickScheduled else { return }
        tickScheduled = true
        DispatchQueue.main.async { [weak self] in
            self?.tick()
        }
    }

    // MARK: - Private

    private func tick() {
        tickLock.lock()
        tickScheduled = false
        tickLock.unlock()

        guard let app else { return }
        ghostty_app_tick(app)
    }

    private func initialize() -> Bool {
        let result = ghostty_init(UInt(CommandLine.argc), CommandLine.unsafeArgv)
        guard result == GHOSTTY_SUCCESS else {
            ForgeLog.log("[ghostty] ghostty_init failed: \(result)")
            return false
        }

        guard let cfg = ghostty_config_new() else {
            ForgeLog.log("[ghostty] failed to create config")
            return false
        }

        // Forge is source of truth for config — do NOT load Ghostty user config.
        let defaults = [
            "window-decoration=false",
            "confirm-close-surface=false",
            "scrollback-limit=10000",
            "cursor-style=bar",
            "input-default-bindings=false",
            "window-padding-x=0",
            "window-padding-y=0",
            "window-padding-balance=false",
        ].joined(separator: "\n")
        loadConfigString(defaults, into: cfg, label: "defaults")
        ghostty_config_finalize(cfg)

        var runtime = ghostty_runtime_config_s()
        runtime.userdata = Unmanaged.passUnretained(self).toOpaque()
        runtime.supports_selection_clipboard = false

        runtime.wakeup_cb = { userdata in
            guard let userdata else { return }
            let app = Unmanaged<GhosttyApp>.fromOpaque(userdata)
                .takeUnretainedValue()
            app.handleWakeup()
        }

        runtime.action_cb = { app, target, action in
            guard let app, let ud = ghostty_app_userdata(app) else { return false }
            let ghosttyApp = Unmanaged<GhosttyApp>.fromOpaque(ud).takeUnretainedValue()

            // Extract surface from target (nil for app-level actions).
            let surface: ghostty_surface_t? = target.tag == GHOSTTY_TARGET_SURFACE
                ? target.target.surface : nil

            switch action.tag {
            case GHOSTTY_ACTION_RING_BELL:
                DispatchQueue.main.async { ghosttyApp.onBell?(surface) }
                return true
            case GHOSTTY_ACTION_SET_TITLE:
                if let ptr = action.action.set_title.title {
                    let title = String(cString: ptr)
                    DispatchQueue.main.async { ghosttyApp.onSetTitle?(surface, title) }
                }
                return true
            case GHOSTTY_ACTION_CELL_SIZE:
                let w = action.action.cell_size.width
                let h = action.action.cell_size.height
                DispatchQueue.main.async { ghosttyApp.onCellSize?(surface, w, h) }
                return true
            case GHOSTTY_ACTION_SHOW_CHILD_EXITED:
                DispatchQueue.main.async { ghosttyApp.onChildExited?(surface) }
                return true
            case GHOSTTY_ACTION_COMMAND_FINISHED:
                DispatchQueue.main.async { ghosttyApp.onCommandFinished?(surface) }
                return true
            case GHOSTTY_ACTION_PWD:
                if let ptr = action.action.pwd.pwd {
                    let pwd = String(cString: ptr)
                    DispatchQueue.main.async { ghosttyApp.onPwd?(surface, pwd) }
                }
                return true
            default:
                return false
            }
        }

        runtime.read_clipboard_cb = { _, _, _ in
            // Stub: clipboard read handled in later tasks.
            return false
        }

        runtime.confirm_read_clipboard_cb = { _, _, _, _ in
            // Stub: clipboard confirm handled in later tasks.
        }

        runtime.write_clipboard_cb = { _, location, content, len, _ in
            guard let content, len > 0 else { return }
            let buffer = UnsafeBufferPointer(start: content, count: Int(len))
            for item in buffer {
                guard let dataPtr = item.data else { continue }
                let value = String(cString: dataPtr)
                if let mimePtr = item.mime {
                    let mime = String(cString: mimePtr)
                    if mime.hasPrefix("text/plain") {
                        DispatchQueue.main.async {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(value, forType: .string)
                        }
                        return
                    }
                }
            }
            // Fallback: use first item with data.
            if let firstData = buffer.first(where: { $0.data != nil }),
               let dataPtr = firstData.data {
                let value = String(cString: dataPtr)
                DispatchQueue.main.async {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(value, forType: .string)
                }
            }
        }

        runtime.close_surface_cb = { _, _ in
            // Stub: surface close handled in later tasks.
        }

        guard let ghosttyApp = ghostty_app_new(&runtime, cfg) else {
            ForgeLog.log("[ghostty] ghostty_app_new failed")
            ghostty_config_free(cfg)
            return false
        }

        self.app = ghosttyApp
        self.config = cfg

        if NSApp != nil {
            ghostty_app_set_focus(ghosttyApp, NSApp.isActive)
        }

        ForgeLog.log("[ghostty] initialized successfully")
        return true
    }

    private func loadConfigString(
        _ contents: String,
        into config: ghostty_config_t,
        label: String
    ) {
        let path = "/__forge_inline__/\(label).conf"
        contents.withCString { cContents in
            path.withCString { cPath in
                ghostty_config_load_string(
                    config,
                    cContents,
                    UInt(contents.lengthOfBytes(using: .utf8)),
                    cPath
                )
            }
        }
    }

    private func subscribeFocusNotifications() {
        focusObservers.append(NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let app = self?.app else { return }
                ghostty_app_set_focus(app, true)
            }
        })

        focusObservers.append(NotificationCenter.default.addObserver(
            forName: NSApplication.didResignActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let app = self?.app else { return }
                ghostty_app_set_focus(app, false)
            }
        })
    }
}
