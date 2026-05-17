@preconcurrency import AppKit
import GhosttyKit

/// Ghostty-backed terminal renderer using MANUAL IO mode.
/// The surface does not start a child process. Instead, data is pushed in via
/// `feed(_:)` and user input arrives via the `io_write_cb` callback.
@MainActor
final class GhosttyRenderer: TerminalRenderer {
    // nonisolated(unsafe): opaque pointers freed in deinit, which is
    // nonisolated in Swift 6. Only mutated on MainActor during init.
    nonisolated(unsafe) private var surface: ghostty_surface_t?
    let nsView: GhosttyNSView
    nonisolated(unsafe) private var callbackContext: Unmanaged<GhosttyCallbackContext>?
    var onInput: ((Data) -> Void)?
    var onResize: ((Int, Int) -> Void)?
    /// Debounce resize to avoid sending intermediate sizes during SwiftUI layout.
    private var pendingResize: DispatchWorkItem?
    var lastReportedSize: (cols: Int, rows: Int)?

    var view: NSView { nsView }

    init(ghosttyApp: GhosttyApp) {
        nsView = GhosttyNSView(frame: .zero)

        guard let app = ghosttyApp.app else {
            ForgeLog.log("[ghostty] Cannot create renderer — app not initialized")
            return
        }

        let context = GhosttyCallbackContext(renderer: self)
        let retained = Unmanaged.passRetained(context)
        self.callbackContext = retained

        var config = ghostty_surface_config_new()
        config.io_mode = GHOSTTY_SURFACE_IO_MANUAL
        config.io_write_cb = { userdata, data, len in
            // Fires from ghostty I/O thread — extract data, then dispatch to main.
            guard let userdata, let data else { return }
            let bytes = Data(bytes: data, count: Int(len))
            DispatchQueue.main.async {
                let ctx = Unmanaged<GhosttyCallbackContext>
                    .fromOpaque(userdata)
                    .takeUnretainedValue()
                ctx.renderer?.onInput?(bytes)
            }
        }
        config.io_write_userdata = retained.toOpaque()
        config.platform_tag = GHOSTTY_PLATFORM_MACOS
        config.platform = ghostty_platform_u(
            macos: ghostty_platform_macos_s(
                nsview: Unmanaged.passUnretained(nsView).toOpaque()
            )
        )
        config.context = GHOSTTY_SURFACE_CONTEXT_SPLIT

        surface = ghostty_surface_new(app, &config)
        nsView.surface = surface

        // Wire resize: debounce to avoid sending intermediate sizes during
        // SwiftUI layout (e.g. full-width → split-width transition).
        nsView.onSurfaceResize = { [weak self] cols, rows in
            guard let self else { return }
            if let last = self.lastReportedSize, last.cols == cols, last.rows == rows { return }
            self.pendingResize?.cancel()
            let work = DispatchWorkItem { [weak self] in
                guard let self else { return }
                self.lastReportedSize = (cols, rows)
                self.onResize?(cols, rows)
            }
            self.pendingResize = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05, execute: work)
        }

        // Wire keyboard input: bypass ghostty's key encoder (Kitty protocol),
        // send raw terminal bytes directly to tmux
        nsView.onKeyInput = { [weak self] data in
            self?.onInput?(data)
        }

        if let surface {
            ghostty_surface_set_content_scale(surface, 2.0, 2.0)
            ForgeLog.log("[ghostty] Surface created successfully")
        } else {
            ForgeLog.log("[ghostty] Failed to create surface")
        }
    }

    /// Public accessor for surface pointer (used by findPaneBySurface).
    var surfaceHandle: ghostty_surface_t? { surface }

    /// Creates a renderer in EXEC mode: Ghostty forks a shell, owns the PTY,
    /// and handles all I/O natively. No onInput/onResize wiring needed.
    init(ghosttyApp: GhosttyApp, cwd: String, env: [String: String] = [:]) {
        nsView = GhosttyNSView(frame: .zero)
        nsView.execMode = true

        guard let app = ghosttyApp.app else {
            ForgeLog.log("[ghostty] Cannot create EXEC renderer — app not initialized")
            return
        }

        var config = ghostty_surface_config_new()
        config.io_mode = GHOSTTY_SURFACE_IO_EXEC
        config.platform_tag = GHOSTTY_PLATFORM_MACOS
        config.platform = ghostty_platform_u(
            macos: ghostty_platform_macos_s(
                nsview: Unmanaged.passUnretained(nsView).toOpaque()
            )
        )
        config.context = GHOSTTY_SURFACE_CONTEXT_SPLIT

        // Build env var array — NSString keeps the UTF-8 pointers alive for the closure.
        var envVars: [ghostty_env_var_s] = env.map { key, value in
            ghostty_env_var_s(
                key: (key as NSString).utf8String,
                value: (value as NSString).utf8String
            )
        }

        cwd.withCString { cwdPtr in
            config.working_directory = cwdPtr
            if envVars.isEmpty {
                config.env_vars = nil
                config.env_var_count = 0
                surface = ghostty_surface_new(app, &config)
            } else {
                envVars.withUnsafeMutableBufferPointer { buf in
                    config.env_vars = buf.baseAddress
                    config.env_var_count = buf.count
                    surface = ghostty_surface_new(app, &config)
                }
            }
        }

        // Defer surface connection until view is in a window (Metal needs it).
        nsView.pendingSurface = surface

        if let surface {
            ForgeLog.log("[ghostty] EXEC surface created, deferred to window (cwd: \(cwd))")
        } else {
            ForgeLog.log("[ghostty] Failed to create EXEC surface")
        }
    }

    func feed(_ data: Data) {
        guard let surface else { return }
        data.withUnsafeBytes { buffer in
            guard let ptr = buffer.baseAddress else { return }
            ghostty_surface_process_output(
                surface,
                ptr.assumingMemoryBound(to: CChar.self),
                UInt(buffer.count)
            )
        }
    }

    func feedScrollback(_ content: String) {
        feed(Data(content.utf8))
    }

    func setFocused(_ focused: Bool) {
        guard let surface else { return }
        ghostty_surface_set_focus(surface, focused)
    }

    /// Exact cell size in points from ghostty's font metrics.
    /// This is the authoritative cell size — not derived from frame/cols math.
    var exactCellSize: CGSize {
        guard let surface else { return .zero }
        let s = ghostty_surface_size(surface)
        guard s.cell_width_px > 0, s.cell_height_px > 0 else { return .zero }
        let scale = nsView.window?.backingScaleFactor ?? 2.0
        return CGSize(
            width: CGFloat(s.cell_width_px) / scale,
            height: CGFloat(s.cell_height_px) / scale
        )
    }

    func setOccluded(_ occluded: Bool) {
        guard let surface else { return }
        ghostty_surface_set_occlusion(surface, occluded)
    }

    deinit {
        if let surface { ghostty_surface_free(surface) }
        callbackContext?.release()
    }
}
