import SwiftUI

struct WindowTabBar: View {
    var session: Session
    var sidebarVisible: Bool = true
    var onToggleSidebar: () -> Void = {}
    @Environment(WorkspaceController.self) var controller
    @State private var gitBranch: String?
    @State private var draggedTabId: String?
    @State private var renamingWindowId: String?
    @State private var renameText = ""

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
                        .help(KeyboardShortcuts.toggleSidebar.tooltip)
                }

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 1) {
                        ForEach(Array(session.windows.enumerated()), id: \.element.id) { index, window in
                            if renamingWindowId == window.id {
                                InlineRenameField(text: $renameText, font: .system(.caption, weight: .regular), onCancel: { renamingWindowId = nil }) {
                                    if !renameText.isEmpty {
                                        controller.renameWindow(window, to: renameText)
                                    }
                                    renamingWindowId = nil
                                }
                                .fixedSize()
                                .frame(height: 28)
                            } else {
                                WindowTab(
                                    window: window,
                                    isActive: window.id == controller.workspace.activeWindowId,
                                    tabIndex: index + 1
                                )
                                .opacity(draggedTabId == window.id ? 0.0 : 1.0)
                                .onDrag {
                                    draggedTabId = window.id
                                    return NSItemProvider(object: window.id as NSString)
                                }
                                .onDrop(of: [.text], delegate: ReorderDropDelegate(
                                    item: window,
                                    items: session.windows,
                                    draggedItemId: $draggedTabId,
                                    onMove: { from, to in
                                        session.windows.move(fromOffsets: from, toOffset: to)
                                    }
                                ))
                                .onTapGesture {
                                    controller.selectWindow(window)
                                }
                                .contextMenu {
                                    Button("Rename...") {
                                        renamingWindowId = window.id
                                        renameText = window.name
                                    }
                                    Divider()
                                    Button("Close Tab", role: .destructive) {
                                        controller.removeWindow(window, in: session)
                                    }
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 4)
                }
                .fixedSize(horizontal: true, vertical: false)

                Color.clear
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
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
                    .help(KeyboardShortcuts.splitHorizontal.tooltip)

                    IconButton(systemName: "rectangle.split.1x2") {
                        controller.splitPane(direction: .vertical)
                    }
                    .frame(width: 28, height: 28)
                    .help(KeyboardShortcuts.splitVertical.tooltip)
                }
                .padding(.trailing, 8)
            }
            .frame(height: 28)
        }
        .background(Color(nsColor: .controlBackgroundColor))
        .onAppear { fetchGitBranch() }
        .onChange(of: session.path) { fetchGitBranch() }
        .onReceive(NotificationCenter.default.publisher(for: .forgeRenameTab)) { _ in
            guard let windowId = controller.workspace.activeWindowId,
                  let window = session.windows.first(where: { $0.id == windowId }) else { return }
            renamingWindowId = window.id
            renameText = window.name
        }
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
    var tabIndex: Int = 0
    @State private var isHovered = false

    var body: some View {
        let modifiers = ModifierKeyMonitor.shared

        VStack(spacing: 0) {
            HStack(spacing: 4) {
                if modifiers.commandPressed && tabIndex >= 1 && tabIndex <= 9 {
                    Text("\(tabIndex)")
                        .font(.system(.caption, weight: .medium))
                        .foregroundStyle(Color.accentColor)
                        .frame(width: 14)
                }
                Text(window.name)
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
