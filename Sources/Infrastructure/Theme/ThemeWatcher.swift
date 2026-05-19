import Foundation

/// Watches ~/.config/forge/themes/ for file changes and posts
/// .forgeThemesChanged. The directory is created on init so users
/// can opt in by simply dropping files into it.
@MainActor
final class ThemeWatcher {
    private var source: DispatchSourceFileSystemObject?
    private var fd: Int32 = -1

    init() {
        let dir = (NSHomeDirectory() as NSString)
            .appendingPathComponent(".config/forge/themes")
        try? FileManager.default.createDirectory(
            atPath: dir, withIntermediateDirectories: true)

        fd = open(dir, O_EVTONLY)
        guard fd >= 0 else {
            ForgeLog.log("[theme] watcher failed to open \(dir): \(errno)")
            return
        }
        let src = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .delete, .extend, .rename],
            queue: .main)
        src.setEventHandler {
            NotificationCenter.default.post(name: .forgeThemesChanged, object: nil)
        }
        src.setCancelHandler { [fd] in
            if fd >= 0 { close(fd) }
        }
        src.resume()
        source = src
    }

    deinit {
        source?.cancel()
    }
}
