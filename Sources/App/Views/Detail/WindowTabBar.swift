import SwiftUI

struct WindowTabBar: View {
    var session: Session
    @Environment(WorkspaceController.self) var controller
    @State private var gitBranch: String?

    private var fullPath: String {
        guard let path = session.path else { return session.name }
        return path.replacingOccurrences(of: NSHomeDirectory(), with: "~")
    }

    private var shortPath: String {
        guard let path = session.path else { return session.name }
        return URL(fileURLWithPath: path).lastPathComponent
    }

    var body: some View {
        VStack(spacing: 0) {
            // Title bar area — path + git branch
            TitleBarRow(fullPath: fullPath, shortPath: shortPath, gitBranch: gitBranch)
                .frame(height: 28)
                .padding(.horizontal, 8)

            // Tab bar
            HStack(spacing: 0) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 1) {
                        ForEach(session.windows) { window in
                            WindowTab(
                                window: window,
                                isActive: window.id == controller.workspace.activeWindowId
                            )
                            .onTapGesture {
                                controller.selectWindow(window)
                            }
                            .contextMenu {
                                Button("Rename...") {}
                                Divider()
                                Button("Close Tab", role: .destructive) {
                                    controller.removeWindow(window)
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 4)
                }

                Spacer()

                Button {
                    controller.addWindow(in: session)
                } label: {
                    Image(systemName: "plus")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 8)
                .help("New Tab")
            }
            .frame(height: 28)
        }
        .background(Color(nsColor: .controlBackgroundColor))
        .onAppear { fetchGitBranch() }
        .onChange(of: session.path) { fetchGitBranch() }
    }

    private func fetchGitBranch() {
        guard let path = session.path else { gitBranch = nil; return }
        Task.detached {
            let process = Process()
            let pipe = Pipe()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
            process.arguments = ["-C", path, "rev-parse", "--abbrev-ref", "HEAD"]
            process.standardOutput = pipe
            process.standardError = FileHandle.nullDevice
            try? process.run()
            process.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let branch = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
            await MainActor.run {
                gitBranch = (branch?.isEmpty == false) ? branch : nil
            }
        }
    }
}

struct TitleBarRow: View {
    let fullPath: String
    let shortPath: String
    let gitBranch: String?

    var body: some View {
        GeometryReader { geo in
            let branchWidth = branchTextWidth(gitBranch)
            let fullPathWidth = textWidth(fullPath)
            let minGap: CGFloat = 10
            let available = geo.size.width - branchWidth - minGap
            let useFull = fullPathWidth <= available

            HStack(spacing: 0) {
                Text(useFull ? fullPath : shortPath)
                    .lineLimit(1)
                    .truncationMode(.middle)

                Spacer(minLength: 10)

                if let branch = gitBranch {
                    Text(branch)
                        .lineLimit(1)
                }
            }
            .font(.system(.caption))
            .foregroundStyle(.tertiary)
            .frame(maxHeight: .infinity)
        }
    }

    private func textWidth(_ text: String) -> CGFloat {
        let font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
        return (text as NSString).size(withAttributes: [.font: font]).width
    }

    private func branchTextWidth(_ branch: String?) -> CGFloat {
        guard let branch else { return 0 }
        return textWidth(branch)
    }
}

struct WindowTab: View {
    var window: Window
    let isActive: Bool

    var body: some View {
        HStack(spacing: 4) {
            Text("\(window.index): \(window.name)")
                .font(.system(.caption, weight: isActive ? .semibold : .regular))
                .lineLimit(1)

            AttentionDot(needsAttention: window.needsAttention, size: 6)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(isActive ? Color.accentColor.opacity(0.15) : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 4))
    }
}
