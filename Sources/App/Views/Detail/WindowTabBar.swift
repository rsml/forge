import SwiftUI

struct WindowTabBar: View {
    var session: Session
    var sidebarVisible: Bool = true
    var onToggleSidebar: () -> Void = {}
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
                .padding(.trailing, 8)
                // When sidebar is hidden, avoid overlapping traffic light buttons
                .padding(.leading, sidebarVisible ? 8 : 78)

            // Tab bar
            HStack(spacing: 0) {
                // Show sidebar toggle when sidebar is hidden
                if !sidebarVisible {
                    IconButton(systemName: "sidebar.left") { onToggleSidebar() }
                        .frame(width: 36, height: 28)
                        .padding(.leading, 8)
                        .help("Show Sidebar")
                }

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 1) {
                        ForEach(session.windows) { window in
                            WindowTab(
                                window: window,
                                isActive: window.id == controller.workspace.activeWindowId
                            )
                            .draggable(window.id)
                            .dropDestination(for: String.self) { droppedIds, _ in
                                guard let droppedId = droppedIds.first,
                                      let from = session.windows.firstIndex(where: { $0.id == droppedId }),
                                      let to = session.windows.firstIndex(where: { $0.id == window.id }),
                                      from != to
                                else { return false }
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    session.windows.move(fromOffsets: IndexSet(integer: from),
                                                         toOffset: to > from ? to + 1 : to)
                                }
                                return true
                            }
                            .onTapGesture {
                                controller.selectWindow(window)
                            }
                            .contextMenu {
                                Button("Rename...") {}
                                Divider()
                                Button("Close Tab", role: .destructive) {
                                    controller.removeWindow(window, in: session)
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 4)
                }

                Spacer()
                    .frame(minWidth: 40, maxHeight: .infinity)
                    .contentShape(Rectangle())
                    .onTapGesture(count: 2) {
                        controller.addWindow(in: session)
                    }
                    .contextMenu {
                        Button("New Tab") {
                            controller.addWindow(in: session)
                        }
                        Button("New Browser Tab") {}
                    }

                HStack(spacing: 0) {
                    IconButton(systemName: "rectangle.split.2x1") {
                        controller.splitPane(direction: .horizontal)
                    }
                    .frame(width: 28, height: 28)
                    .help("Split Horizontally")

                    IconButton(systemName: "rectangle.split.1x2") {
                        controller.splitPane(direction: .vertical)
                    }
                    .frame(width: 28, height: 28)
                    .help("Split Vertically")
                }
                .padding(.trailing, 8)
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
    @State private var isHovered = false

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 4) {
                Text("\(window.index): \(window.name)")
                    .font(.system(.caption, weight: .regular))
                    .foregroundStyle((isActive || isHovered) ? .primary : .secondary)
                    .lineLimit(1)

                AttentionDot(needsAttention: window.needsAttention, size: 6)
            }
            .padding(.horizontal, 10)
            .frame(maxHeight: .infinity)
            .offset(y: 1)

            // Active tab indicator — flush to bottom
            RoundedRectangle(cornerRadius: 1)
                .fill(isActive ? Color.accentColor.opacity(0.6) : Color.clear)
                .frame(height: 2)
                .padding(.horizontal, 6)
        }
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
    }
}
