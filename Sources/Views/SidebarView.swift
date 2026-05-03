import SwiftUI

struct SidebarView: View {
    @Environment(TmuxController.self) var tmux
    @State private var hoveredSessionId: String?
    @State private var showNewProject = false

    var body: some View {
        @Bindable var tmux = tmux
        List(selection: $tmux.state.activeSessionId) {
            ForEach(tmux.state.sessions) { session in
                SessionRow(
                    session: session,
                    isHovered: hoveredSessionId == session.id
                )
                .tag(session.id)
                .onHover { hovering in
                    withAnimation(.easeInOut(duration: 0.15)) {
                        hoveredSessionId = hovering ? session.id : nil
                    }
                }
                .contextMenu {
                    SessionContextMenu(session: session)
                }
            }
            .onMove { source, destination in
                tmux.state.sessions.move(fromOffsets: source, toOffset: destination)
            }
        }
        .listStyle(.sidebar)
        .safeAreaInset(edge: .bottom) {
            HStack {
                Button {
                    showNewProject = true
                } label: {
                    Label("New Project", systemImage: "plus")
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)

                Spacer()
            }
            .background(.bar)
        }
        .sheet(isPresented: $showNewProject) {
            ProjectPickerView()
        }
        .navigationTitle("Forge")
        .onChange(of: tmux.state.activeSessionId) { _, newId in
            if let newId, let session = tmux.state.session(byId: newId) {
                tmux.selectSession(session)
            }
        }
    }
}

// MARK: - Session Row (collapsed/expanded)

struct SessionRow: View {
    var session: TmuxSession
    let isHovered: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                StatusDot(status: session.aggregateStatus)

                Text(session.name)
                    .font(.system(.body, weight: .medium))
                    .lineLimit(1)

                Spacer()

                if session.windowCount > 1 {
                    Text("\(session.windowCount)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if isHovered && !session.windows.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(session.windows) { window in
                        WindowRow(window: window)
                    }
                }
                .padding(.leading, 20)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(.vertical, 2)
    }
}

struct WindowRow: View {
    var window: TmuxWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            HStack(spacing: 6) {
                Image(systemName: "rectangle.split.3x1")
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                Text(window.name)
                    .font(.caption)
                    .lineLimit(1)

                if window.active {
                    Circle()
                        .fill(.blue)
                        .frame(width: 4, height: 4)
                }
            }

            ForEach(window.panes) { pane in
                PaneRow(pane: pane)
            }
        }
    }
}

struct PaneRow: View {
    var pane: TmuxPane

    var body: some View {
        HStack(spacing: 6) {
            StatusDot(status: pane.status, size: 6)

            Text(pane.currentCommand)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(.leading, 16)
    }
}

// MARK: - Status Indicator

struct StatusDot: View {
    let status: PaneStatus
    var size: CGFloat = 8

    var color: Color {
        switch status {
        case .idle: return .gray
        case .running: return .green
        case .needsAttention: return .orange
        case .error: return .red
        }
    }

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: size, height: size)
    }
}

// MARK: - Context Menu

struct SessionContextMenu: View {
    var session: TmuxSession
    @Environment(TmuxController.self) var tmux

    var body: some View {
        Button("Rename...") {
            // TODO: inline rename
        }

        Divider()

        Button("New Window") {
            tmux.newWindow(in: session)
        }

        Divider()

        Button("Close Session", role: .destructive) {
            tmux.killSession(session)
        }
    }
}
