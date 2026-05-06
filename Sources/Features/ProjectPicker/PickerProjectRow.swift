import SwiftUI

struct PickerProjectRow: View {
    let path: String

    private var name: String {
        guard !path.isEmpty else { return "(unknown)" }
        return URL(fileURLWithPath: path).lastPathComponent
    }
    private var displayPath: String { path.replacingOccurrences(of: NSHomeDirectory(), with: "~") }
    private var isGitRepo: Bool {
        guard !path.isEmpty else { return false }
        return FileManager.default.fileExists(atPath: (path as NSString).appendingPathComponent(".git"))
    }

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: isGitRepo ? "folder.badge.gearshape" : "folder")
                .foregroundStyle(.secondary)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 1) {
                Text(name)
                    .lineLimit(1)
                Text(displayPath)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .textSelection(.disabled)
    }
}

@MainActor
final class SortMenuTarget: NSObject {
    static let shared = SortMenuTarget()
    var onSelect: ((String) -> Void)?

    @objc func select(_ sender: NSMenuItem) {
        if let value = sender.representedObject as? String {
            onSelect?(value)
        }
    }
}
