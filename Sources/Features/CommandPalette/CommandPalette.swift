import SwiftUI
import ForgeCore

struct CommandPalette: View {
    @Environment(WorkspaceController.self) var controller
    @Environment(CommandRegistry.self) private var registry
    @Binding var isPresented: Bool
    @State private var query = ""
    @State private var selectedIndex = 0
    @State private var useMouseSelection = true
    @FocusState private var isFieldFocused: Bool

    private var results: [CommandItem] {
        let sorted = registry.commands.sorted { $0.name < $1.name }
        if query.isEmpty {
            var items: [CommandItem] = []
            for project in controller.workspace.projects {
                items.append(CommandItem(title: project.name, subtitle: "Project", icon: "folder", action: { [weak controller] in
                    controller?.selectProject(project)
                }))
            }
            let commonCommands = ["go", "new-project", "new-tab", "settings", "theme", "toggle-sidebar"]
            let common = sorted.filter { commonCommands.contains($0.name) }
            for cmd in common {
                items.append(CommandItem(command: cmd))
            }
            return items
        }
        if query.hasPrefix("/") {
            let afterSlash = String(query.dropFirst())
            let commandPart = afterSlash.split(separator: " ", maxSplits: 1).first.map(String.init) ?? afterSlash
            let searchTerm = commandPart.trimmingCharacters(in: .whitespaces).lowercased()
            if searchTerm.isEmpty {
                return sorted.map { CommandItem(command: $0) }
            }
            return sorted
                .filter { $0.name.lowercased().contains(searchTerm) }
                .map { CommandItem(command: $0) }
        }
        // Plain text: fuzzy search sessions + windows
        let term = query.lowercased()
        var items: [CommandItem] = []
        for project in controller.workspace.projects {
            if project.name.lowercased().contains(term) {
                items.append(CommandItem(title: project.name, subtitle: "Project", icon: "folder", action: { [weak controller] in
                    controller?.selectProject(project)
                }))
            }
            for window in project.tabs {
                if window.name.lowercased().contains(term) {
                    items.append(CommandItem(title: window.name, subtitle: project.name, icon: "rectangle.topthird.inset.filled", action: { [weak controller] in
                        controller?.selectProject(project)
                        controller?.selectTab(window)
                    }))
                }
            }
        }
        return items
    }

    var body: some View {
        VStack(spacing: 0) {
            // Search field
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Type a command, project, or tab name...", text: $query)
                    .textFieldStyle(.plain)
                    .font(.system(size: 16))
                    .focused($isFieldFocused)
                    .onSubmit { executeSelected() }
                    .onChange(of: query) {
                        selectedIndex = 0
                        useMouseSelection = false
                    }
            }
            .padding(12)

            if !results.isEmpty {
                Divider()

                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(Array(results.enumerated().prefix(20)), id: \.offset) { index, item in
                                CommandRow(item: item, isSelected: index == selectedIndex)
                                    .id(index)
                                    .contentShape(Rectangle())
                                    .onHover { hovering in
                                        if hovering {
                                            useMouseSelection = true
                                            selectedIndex = index
                                        }
                                    }
                                    .onTapGesture {
                                        selectedIndex = index
                                        executeSelected()
                                    }
                            }
                        }
                    }
                    .frame(maxHeight: 300)
                    .onChange(of: selectedIndex) { _, newValue in
                        proxy.scrollTo(newValue, anchor: .center)
                    }
                }
            }
        }
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                isFieldFocused = true
            }
        }
        .onKeyPress(.escape) { dismiss(); return .handled }
        .onKeyPress(.upArrow) {
            useMouseSelection = false
            selectedIndex = max(0, selectedIndex - 1)
            return .handled
        }
        .onKeyPress(.downArrow) {
            useMouseSelection = false
            selectedIndex = min(results.count - 1, selectedIndex + 1)
            return .handled
        }
    }

    private func executeSelected() {
        guard selectedIndex < results.count else { return }
        let item = results[selectedIndex]
        let arg = argumentFrom(query)
        dismiss()
        item.execute(arg)
    }

    private func dismiss() {
        isPresented = false
        query = ""
        selectedIndex = 0
    }

    private func argumentFrom(_ query: String) -> String {
        if query.hasPrefix("/") {
            let parts = query.dropFirst().split(separator: " ", maxSplits: 1)
            return parts.count > 1 ? String(parts[1]) : ""
        }
        return query
    }
}

struct CommandRow: View {
    let item: CommandItem
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: item.icon)
                .frame(width: 20)
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 1) {
                Text(item.title)
                    .font(.system(size: 13))
                if !item.subtitle.isEmpty {
                    Text(item.subtitle)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            if let hint = item.shortcutHint {
                Text(hint)
                    .font(.system(size: 12, design: .rounded))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(isSelected ? Color.accentColor.opacity(0.2) : Color.clear)
    }
}

struct CommandItem {
    let title: String
    let subtitle: String
    let icon: String
    let shortcutHint: String?
    let execute: (String) -> Void

    init(title: String, subtitle: String, icon: String, action: @escaping () -> Void) {
        self.title = title
        self.subtitle = subtitle
        self.icon = icon
        self.shortcutHint = nil
        self.execute = { _ in action() }
    }

    init(command: Command) {
        self.title = "/\(command.name)"
        self.subtitle = command.description
        self.icon = command.icon
        self.shortcutHint = command.shortcutHint
        self.execute = command.execute
    }
}
