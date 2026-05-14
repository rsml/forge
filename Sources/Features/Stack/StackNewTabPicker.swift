import SwiftUI
import ForgeCore

struct StackNewTabPicker: View {
    @Environment(WorkspaceController.self) private var controller
    @Environment(AppState.self) private var appState
    var onDismiss: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Text("New Tab")
                .font(.system(size: 13, weight: .semibold))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)

            Divider()

            ScrollView {
                VStack(spacing: 0) {
                    ForEach(controller.workspace.projects) { project in
                        ProjectRow(project: project) {
                            controller.addTab(in: project)
                            onDismiss()
                        }
                    }
                }
            }
            .frame(maxHeight: 300)

            Divider()

            Button {
                appState.activeModal = .projectPicker
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "plus")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                    Text("New Project...")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .onHover { hovering in
                if hovering { NSCursor.arrow.push() } else { NSCursor.pop() }
            }
        }
        .onKeyPress(.escape) { onDismiss(); return .handled }
    }
}

private struct ProjectRow: View {
    let project: Project
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack {
                Text(project.name)
                    .font(.system(size: 12, weight: .medium))
                Spacer()
                Text("\(project.tabs.count) tab\(project.tabs.count == 1 ? "" : "s")")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(isHovered ? Color.white.opacity(0.06) : Color.clear)
                    .padding(.horizontal, 8)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovered = hovering
            if hovering { NSCursor.arrow.push() } else { NSCursor.pop() }
        }
    }
}
