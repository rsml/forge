import SwiftUI

struct SessionDetailView: View {
    var session: Session
    var sidebarVisible: Bool = true
    var onToggleSidebar: () -> Void = {}
    @Environment(WorkspaceController.self) var controller
    @State private var gitBranch: String?

    private var tabBarPosition: String {
        ForgeConfigStore.shared.config.general?.tabBarPosition ??
        ForgeConfigStore.shared.config.terminal?.tabBarPosition ??
        ForgeConfigStore.shared.config.appearance?.tabBarPosition ?? "top"
    }

    private var fullPath: String {
        guard let path = session.path else { return session.name }
        return path.replacingOccurrences(of: NSHomeDirectory(), with: "~")
    }

    private var shortPath: String {
        guard let path = session.path else { return session.name }
        return URL(fileURLWithPath: path).lastPathComponent
    }

    private var sidebarPosition: String {
        ForgeConfigStore.shared.config.general?.sidebarPosition ?? "left"
    }

    private var chromeBackground: Color {
        ForgeConfigStore.shared.resolvedTheme?.background ?? Color(nsColor: .controlBackgroundColor)
    }

    var body: some View {
        VStack(spacing: 0) {
            // Title bar always at top
            TitleBarRow(fullPath: fullPath, shortPath: shortPath, gitBranch: gitBranch)
                .frame(height: 28)
                .padding(.trailing, (!sidebarVisible && sidebarPosition == "right") ? 52 : 8)
                .padding(.leading, sidebarVisible ? 8 : 78)
                .background(chromeBackground)

            if tabBarPosition == "bottom" {
                TerminalArea(session: session)
                WindowTabBar(session: session, sidebarVisible: sidebarVisible, sidebarPosition: sidebarPosition, onToggleSidebar: onToggleSidebar)
            } else {
                WindowTabBar(session: session, sidebarVisible: sidebarVisible, sidebarPosition: sidebarPosition, onToggleSidebar: onToggleSidebar)
                TerminalArea(session: session)
            }
        }
        .toolbar(.hidden, for: .automatic)
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
