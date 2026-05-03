import SwiftUI

struct SessionDetailView: View {
    var session: TmuxSession
    @Environment(TmuxController.self) var tmux

    var body: some View {
        VStack(spacing: 0) {
            WindowTabBar(session: session)

            if let activeWindow = session.windows.first(where: { $0.id == tmux.state.activeWindowId })
                ?? session.windows.first {
                TerminalArea(window: activeWindow)
            } else {
                ContentUnavailableView(
                    "No Windows",
                    systemImage: "rectangle.on.rectangle.slash",
                    description: Text("This session has no windows.")
                )
            }
        }
    }
}

// MARK: - Horizontal Tab Bar (tmux windows)

struct WindowTabBar: View {
    var session: TmuxSession
    @Environment(TmuxController.self) var tmux

    var body: some View {
        HStack(spacing: 0) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 1) {
                    ForEach(session.windows) { window in
                        WindowTab(
                            window: window,
                            isActive: window.id == tmux.state.activeWindowId
                        )
                        .onTapGesture {
                            tmux.selectWindow(window)
                        }
                        .contextMenu {
                            Button("Rename...") {
                                // TODO: inline rename
                            }
                            Divider()
                            Button("Close Window", role: .destructive) {
                                tmux.killWindow(window)
                            }
                        }
                    }
                }
                .padding(.horizontal, 4)
            }

            Spacer()

            Button {
                tmux.newWindow(in: session)
            } label: {
                Image(systemName: "plus")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 8)
        }
        .frame(height: 32)
        .background(Color(nsColor: .controlBackgroundColor))
    }
}

struct WindowTab: View {
    var window: TmuxWindow
    let isActive: Bool

    var body: some View {
        HStack(spacing: 4) {
            Text("\(window.index): \(window.name)")
                .font(.system(.caption, weight: isActive ? .semibold : .regular))
                .lineLimit(1)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(isActive ? Color.accentColor.opacity(0.15) : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 4))
    }
}

// MARK: - Terminal Area

struct TerminalArea: View {
    var window: TmuxWindow
    @Environment(TmuxController.self) var tmux

    var body: some View {
        ForgeTerminalView(
            sessionName: currentSessionName,
            tmux: tmux
        )
        .background(Color(red: 0.1, green: 0.1, blue: 0.1))
    }

    private var currentSessionName: String {
        if let session = tmux.state.sessions.first(where: { s in
            s.windows.contains(where: { $0.id == window.id })
        }) {
            return session.name
        }
        return ""
    }
}
