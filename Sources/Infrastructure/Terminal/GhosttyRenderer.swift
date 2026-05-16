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

        if let surface {
            // Set initial Retina scale — viewDidMoveToWindow updates later.
            ghostty_surface_set_content_scale(surface, 2.0, 2.0)
            ForgeLog.log("[ghostty] Surface created successfully")
        } else {
            ForgeLog.log("[ghostty] Failed to create surface")
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

    func setOccluded(_ occluded: Bool) {
        guard let surface else { return }
        ghostty_surface_set_occlusion(surface, occluded)
    }

    deinit {
        if let surface { ghostty_surface_free(surface) }
        callbackContext?.release()
    }
}
