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
    /// Fires on every chunk of PTY output bytes. Used by the native PTY
    /// attention watcher to detect BEL and scan for content patterns.
    /// Invoked on the main queue regardless of which thread produced the data.
    var onOutput: ((Data) -> Void)?
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

    /// Write raw bytes to the pane's input. Used by the debug server for
    /// automated testing — equivalent to the user typing.
    func sendInput(_ data: Data) {
        data.withUnsafeBytes { buf in
            guard let ptr = buf.baseAddress else { return }
            if externalFD >= 0 {
                _ = Darwin.write(externalFD, ptr, buf.count)
            } else if let surface {
                ghostty_surface_text(surface, ptr.assumingMemoryBound(to: CChar.self), UInt(buf.count))
            }
        }
    }

    /// PTY master fd for EXEC mode surfaces. -1 if unavailable.
    /// Used by DaemonAdapter to send fd for persistence.
    var ptyFD: Int32 {
        guard let surface else { return -1 }
        return ghostty_surface_pty_fd(surface)
    }

    /// Foreground process PID.
    var foregroundPID: Int32 {
        guard let surface else { return 0 }
        return Int32(ghostty_surface_foreground_pid(surface))
    }

    /// Creates a renderer for reconnecting to a pre-existing PTY fd.
    /// Uses MANUAL IO mode with a background read thread on the fd.
    /// Input is written directly to the fd (no tmux send-keys).
    init(ghosttyApp: GhosttyApp, fd: Int32) {
        nsView = GhosttyNSView(frame: .zero)
        nsView.execMode = true // native key handling

        guard let app = ghosttyApp.app else {
            ForgeLog.log("[ghostty] Cannot create EXTERNAL_FD renderer — app not initialized")
            return
        }

        let context = GhosttyCallbackContext(renderer: self)
        let retained = Unmanaged.passRetained(context)
        self.callbackContext = retained

        var config = ghostty_surface_config_new()
        config.io_mode = GHOSTTY_SURFACE_IO_MANUAL
        config.io_write_cb = { userdata, data, len in
            guard let userdata, let data else { return }
            // Write directly to the PTY fd
            let ctx = Unmanaged<GhosttyCallbackContext>
                .fromOpaque(userdata)
                .takeUnretainedValue()
            if let renderer = ctx.renderer, renderer.externalFD >= 0 {
                _ = Darwin.write(renderer.externalFD, data, Int(len))
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
        nsView.pendingSurface = surface

        self.externalFD = fd

        // DON'T start reading yet — the surface has no size (0x0 grid).
        // Output read now would be processed at 0x0 and lost.
        // The read loop starts when the view gets its first valid frame
        // (via onSurfaceResize), which means the surface is in a window
        // and sized. The PTY kernel buffer holds any pending output until then.
        nsView.onSurfaceResize = { [weak self] _, _ in
            guard let self, self.readThread == nil, self.externalFD >= 0 else { return }
            self.startReadLoop(fd: self.externalFD)
            ForgeLog.log("[ghostty] EXTERNAL_FD read loop started after surface sized (fd=\(self.externalFD))")
            // Only need this once — clear the callback
            self.nsView.onSurfaceResize = nil
        }

        if let surface {
            ForgeLog.log("[ghostty] EXTERNAL_FD surface created, read deferred to sizing (fd=\(fd))")
        } else {
            ForgeLog.log("[ghostty] Failed to create EXTERNAL_FD surface")
        }
    }

    /// The external PTY fd for reconnected surfaces. -1 if not applicable.
    nonisolated(unsafe) private(set) var externalFD: Int32 = -1
    private var readThread: Thread?

    /// Stored reconnection context for event-driven reconnection.
    private var reconnectPaneId: String?
    private var reconnectPid: Int32 = 0
    private var reconnected = false

    /// Configure this EXTERNAL_FD renderer for event-driven reconnection.
    /// Reconnection work (scrollback, read loop) fires once on first valid size.
    /// TIOCSWINSZ is sent on every resize (MANUAL mode doesn't resize the PTY).
    func configureForReconnect(paneId: String, pid: Int32) {
        self.reconnectPaneId = paneId
        self.reconnectPid = pid

        nsView.onSurfaceResize = { [weak self] cols, rows in
            guard let self else { return }
            guard cols > 0, rows > 0 else { return }

            // One-time reconnection work
            if !self.reconnected {
                self.reconnected = true
                self.loadScrollback(paneId: paneId)
                if self.readThread == nil, self.externalFD >= 0 {
                    self.startReadLoop(fd: self.externalFD)
                }
                self.startScrollbackLog(paneId: paneId)
                ForgeLog.log("[ghostty] Reconnected pane \(paneId): \(cols)x\(rows) (event-driven)")
            }

            // Send TIOCSWINSZ on every resize — MANUAL mode surfaces
            // don't resize the PTY automatically (unlike EXEC mode).
            // Toggle size first: if the PTY already has this size (same as
            // previous session), the shell won't redraw. A brief size change
            // forces the shell to handle a genuine resize → redraw prompt.
            let frame = self.nsView.frame
            var ws = winsize()
            ws.ws_xpixel = UInt16(frame.width)
            ws.ws_ypixel = UInt16(frame.height)
            ws.ws_col = UInt16(max(1, cols - 1))
            ws.ws_row = UInt16(rows)
            _ = ioctl(self.externalFD, TIOCSWINSZ, &ws)
            ws.ws_col = UInt16(cols)
            _ = ioctl(self.externalFD, TIOCSWINSZ, &ws)
            if pid > 0 { kill(pid, SIGWINCH) }
        }
    }

    /// Scrollback log file for this surface. PTY output is tee'd here
    /// during normal operation. On reconnect, fed into the new surface.
    private var scrollbackLogPath: String?
    private var scrollbackLogHandle: FileHandle?

    /// Start logging PTY output to a file for scrollback persistence.
    func startScrollbackLog(paneId: String) {
        let dir = NSHomeDirectory() + "/.config/forge/scrollback"
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        let path = dir + "/\(paneId).log"
        FileManager.default.createFile(atPath: path, contents: nil)
        scrollbackLogPath = path
        scrollbackLogHandle = FileHandle(forWritingAtPath: path)
        scrollbackLogHandle?.seekToEndOfFile()
    }

    /// Append data to the scrollback log (called from the read thread).
    private func appendToScrollbackLog(_ data: Data) {
        scrollbackLogHandle?.write(data)
        // Cap at 256KB — truncate from the beginning
        if let path = scrollbackLogPath,
           let attrs = try? FileManager.default.attributesOfItem(atPath: path),
           let size = attrs[.size] as? Int, size > 256 * 1024 {
            if let data = try? Data(contentsOf: URL(fileURLWithPath: path)) {
                let trimmed = data.suffix(128 * 1024) // keep last 128KB
                try? trimmed.write(to: URL(fileURLWithPath: path))
                scrollbackLogHandle = FileHandle(forWritingAtPath: path)
                scrollbackLogHandle?.seekToEndOfFile()
            }
        }
    }

    /// Load and feed saved scrollback into this surface.
    func loadScrollback(paneId: String) {
        let path = NSHomeDirectory() + "/.config/forge/scrollback/\(paneId).log"
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
              !data.isEmpty else { return }
        feed(data)
        ForgeLog.log("[ghostty] Fed \(data.count) bytes of scrollback for pane \(paneId)")
    }

    private func startReadLoop(fd: Int32) {
        let thread = Thread {
            // Ensure fd is in blocking mode for the read loop
            let flags = fcntl(fd, F_GETFL)
            if flags == -1 {
                let err = String(cString: strerror(errno))
                DispatchQueue.main.async {
                    ForgeLog.log("[ghostty] EXTERNAL_FD fd=\(fd) is INVALID: \(err)")
                }
                return
            }
            if flags & O_NONBLOCK != 0 {
                _ = fcntl(fd, F_SETFL, flags & ~O_NONBLOCK)
            }

            let bufSize = 8192
            let buf = UnsafeMutableRawPointer.allocate(byteCount: bufSize, alignment: 1)
            defer { buf.deallocate() }
            while true {
                let n = Darwin.read(fd, buf, bufSize)
                if n < 0 {
                    let err = String(cString: strerror(errno))
                    DispatchQueue.main.async {
                        ForgeLog.log("[ghostty] EXTERNAL_FD read error on fd=\(fd): \(err)")
                    }
                    break
                }
                if n == 0 {
                    DispatchQueue.main.async {
                        ForgeLog.log("[ghostty] EXTERNAL_FD fd=\(fd) EOF (process exited)")
                    }
                    break
                }
                let data = Data(bytes: buf, count: n)
                // Tee to scrollback log (on read thread, non-blocking)
                self.appendToScrollbackLog(data)
                DispatchQueue.main.async { [weak self] in
                    self?.feed(data)
                    self?.onOutput?(data)
                }
            }
        }
        thread.name = "forged-fd-\(fd)"
        thread.start()
        readThread = thread
    }

    /// Creates a renderer in EXEC mode: Ghostty forks a shell, owns the PTY,
    /// and handles all I/O natively. No onInput/onResize wiring needed.
    init(ghosttyApp: GhosttyApp, cwd: String, env: [String: String] = [:]) {
        nsView = GhosttyNSView(frame: .zero)
        nsView.execMode = true

        guard let app = ghosttyApp.app else {
            ForgeLog.log("[ghostty] Cannot create EXEC renderer — app not initialized")
            return
        }

        let context = GhosttyCallbackContext(renderer: self)
        let retained = Unmanaged.passRetained(context)
        self.callbackContext = retained

        var config = ghostty_surface_config_new()
        config.io_mode = GHOSTTY_SURFACE_IO_EXEC
        config.platform_tag = GHOSTTY_PLATFORM_MACOS
        config.platform = ghostty_platform_u(
            macos: ghostty_platform_macos_s(
                nsview: Unmanaged.passUnretained(nsView).toOpaque()
            )
        )
        config.context = GHOSTTY_SURFACE_CONTEXT_SPLIT

        // Wire output callback for scrollback logging (fires on Ghostty's I/O thread)
        #if GHOSTTY_HAS_IO_READ_CB
        config.io_read_cb = { userdata, data, len in
            guard let userdata, let data else { return }
            let bytes = Data(bytes: data, count: Int(len))
            let ctx = Unmanaged<GhosttyCallbackContext>
                .fromOpaque(userdata)
                .takeUnretainedValue()
            ctx.renderer?.appendToScrollbackLog(bytes)
            // Hop to main for attention detection — onOutput touches @Observable
            // pane state via PaneActivityWatcher.
            DispatchQueue.main.async {
                ctx.renderer?.onOutput?(bytes)
            }
        }
        config.io_read_userdata = retained.toOpaque()
        #endif

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
