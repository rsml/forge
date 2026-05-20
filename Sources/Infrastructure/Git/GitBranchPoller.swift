import Foundation
import Observation
import ForgeCore

/// Polls `git rev-parse --abbrev-ref HEAD` for the active project and
/// publishes the result to title-bar consumers.
///
/// Posts `forgeWindowTitleChanged` whenever the resolved branch changes.
@Observable
@MainActor
final class GitBranchPoller {
    private(set) var branch: String?

    private weak var workspace: Workspace?
    private var pollTask: Task<Void, Never>?

    func start(workspace: Workspace) {
        self.workspace = workspace
        pollTask?.cancel()
        pollTask = Task { [weak self] in
            await self?.refresh()
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(5))
                guard !Task.isCancelled else { break }
                await self?.refresh()
            }
        }
    }

    func stop() {
        pollTask?.cancel()
        pollTask = nil
    }

    /// Re-fetch the branch immediately. Useful for explicit invalidation
    /// (e.g. project switch) so the label updates without waiting for the
    /// next poll tick.
    func refresh() async {
        guard let workspace else { return }
        let newBranch: String?
        if let path = workspace.activeProject?.path {
            newBranch = await Self.currentBranch(at: path)
        } else {
            newBranch = nil
        }
        if newBranch != branch {
            branch = newBranch
            NotificationCenter.default.post(name: .forgeWindowTitleChanged, object: nil)
        }
    }

    private static func currentBranch(at path: String) async -> String? {
        await withCheckedContinuation { cont in
            let process = Process()
            let pipe = Pipe()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
            process.arguments = ["-C", path, "rev-parse", "--abbrev-ref", "HEAD"]
            process.standardOutput = pipe
            process.standardError = FileHandle.nullDevice
            do {
                try process.run()
                process.waitUntilExit()
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                let branch = String(data: data, encoding: .utf8)?
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                cont.resume(returning: (branch?.isEmpty == false) ? branch : nil)
            } catch {
                cont.resume(returning: nil)
            }
        }
    }
}
