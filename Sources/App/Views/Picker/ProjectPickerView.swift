import SwiftUI

enum ProjectSortMode: String, CaseIterable {
    case recent = "Recent"
    case mostUsed = "Most Opened"
    case alphabetical = "Alphabetical"
}

struct ProjectPickerView: View {
    var onDismiss: (() -> Void)? = nil
    @Environment(WorkspaceController.self) var controller
    @Environment(\.dismiss) var dismiss
    @State private var searchText = ""
    @State private var selectedPath: String?
    @State private var recentPaths: [String] = []
    @State private var errorMessage: String?
    @State private var sortMode: ProjectSortMode = .recent
    @FocusState private var isSearchFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Filter recent projects...", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(.title3)
                    .focused($isSearchFocused)
                    .onSubmit { openProject() }
            }
            .padding(16)

            Divider()

            ScrollView {
                let sorted = sortedPaths
                if !sorted.isEmpty {
                    VStack(spacing: 0) {
                        HStack {
                            Text(sortMode.rawValue)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .textCase(.uppercase)
                            Spacer()
                            Menu {
                                ForEach(ProjectSortMode.allCases, id: \.self) { mode in
                                    Button {
                                        sortMode = mode
                                    } label: {
                                        if mode == sortMode {
                                            Label(mode.rawValue, systemImage: "checkmark")
                                        } else {
                                            Text(mode.rawValue)
                                        }
                                    }
                                }
                            } label: {
                                Image(systemName: "chevron.down")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            .menuStyle(.borderlessButton)
                            .fixedSize()
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)

                        ForEach(sorted, id: \.self) { path in
                            ProjectRow(path: path, openCount: openCount(for: path))
                                .padding(.vertical, 8)
                                .padding(.horizontal, 16)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(
                                    RoundedRectangle(cornerRadius: 4)
                                        .fill(selectedPath == path ? Color.accentColor.opacity(0.3) : Color.clear)
                                        .padding(.horizontal, 8)
                                )
                                .contentShape(Rectangle())
                                .onTapGesture(count: 2) {
                                    selectedPath = path
                                    openProject()
                                }
                                .onTapGesture(count: 1) {
                                    selectedPath = path
                                }
                                .onHover { hovering in
                                    if hovering { NSCursor.arrow.push() } else { NSCursor.pop() }
                                }
                        }
                    }
                } else if !searchText.isEmpty {
                    VStack {
                        Spacer()
                        Text("No matches found")
                            .foregroundStyle(.secondary)
                            .font(.callout)
                            .frame(maxWidth: .infinity)
                        Spacer()
                    }
                    .frame(height: 200)
                }
            }
            .frame(idealHeight: 500)

            Divider()

            if let errorMessage {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                Divider()
            }

            HStack {
                Button("Browse...") { browseForFolder() }
                Spacer()
                Button("Cancel") { close() }.keyboardShortcut(.cancelAction)
                Button("Open") { openProject() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(resolvedPath == nil)
            }
            .padding(16)
        }
        .onKeyPress(.escape) { close(); return .handled }
        .onAppear {
            recentPaths = ForgeConfigStore.shared.config.recentDirectories
            if recentPaths.isEmpty {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    browseForFolder()
                }
                return  // Don't focus search since browse dialog will show
            }
            // Auto-select first item
            if selectedPath == nil, let first = recentPaths.first {
                selectedPath = first
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                isSearchFocused = true
            }
        }
    }

    private func close() {
        if let onDismiss { onDismiss() } else { dismiss() }
    }

    // MARK: - Display

    private var sortedPaths: [String] {
        let filtered: [String]
        if searchText.isEmpty {
            filtered = recentPaths
        } else {
            let term = searchText.lowercased()
            filtered = recentPaths.filter { path in
                guard !path.isEmpty else { return false }
                return path.lowercased().contains(term) ||
                    URL(fileURLWithPath: path).lastPathComponent.lowercased().contains(term)
            }
        }
        switch sortMode {
        case .recent:
            return filtered
        case .mostUsed:
            let counts = ForgeConfigStore.shared.config.projectOpenCounts ?? [:]
            return filtered.sorted { (counts[$0] ?? 0) > (counts[$1] ?? 0) }
        case .alphabetical:
            return filtered.sorted {
                URL(fileURLWithPath: $0).lastPathComponent.localizedCaseInsensitiveCompare(
                    URL(fileURLWithPath: $1).lastPathComponent) == .orderedAscending
            }
        }
    }

    private func openCount(for path: String) -> Int {
        ForgeConfigStore.shared.config.projectOpenCounts?[path] ?? 0
    }

    /// The path that would be opened — either selected row, valid typed path, or nil
    private var resolvedPath: String? {
        if let selectedPath { return selectedPath }
        let expanded = (searchText as NSString).expandingTildeInPath
        if expanded.hasPrefix("/") && isDirectory(expanded) { return expanded }
        return nil
    }

    // MARK: - Actions

    private func openProject() {
        guard let path = resolvedPath else {
            if !searchText.isEmpty {
                let expanded = (searchText as NSString).expandingTildeInPath
                if !expanded.hasPrefix("/") {
                    errorMessage = "Enter a full path (e.g. ~/Projects/myapp) or select from the list."
                } else if !isDirectory(expanded) {
                    errorMessage = "Directory not found: \(expanded)"
                }
            }
            return
        }
        // Guard against re-opening an already open project — just switch to it
        if let existing = controller.workspace.sessions.first(where: { $0.path == path }) {
            saveToRecent(path)
            controller.selectSession(existing)
            close()
            return
        }
        // Validate path still exists (may have been deleted between selection and click)
        guard isDirectory(path) else {
            errorMessage = "Directory no longer exists: \(path)"
            selectedPath = nil
            return
        }
        // Derive a unique session name to avoid tmux session name conflicts
        let baseName = path.isEmpty ? "project" : URL(fileURLWithPath: path).lastPathComponent
        let existingNames = Set(controller.workspace.sessions.map(\.name))
        let sessionName = uniqueSessionName(baseName, existing: existingNames)
        errorMessage = nil
        saveToRecent(path)
        Task { @MainActor in
            await controller.addSession(name: sessionName, path: path)
            close()
        }
    }

    private func browseForFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.message = "Choose a project directory"
        if panel.runModal() == .OK, let url = panel.url {
            let path = url.path
            if let existing = controller.workspace.sessions.first(where: { $0.path == path }) {
                saveToRecent(path)
                controller.selectSession(existing)
                close()
                return
            }
            guard isDirectory(path) else { return }
            let baseName = URL(fileURLWithPath: path).lastPathComponent
            let existingNames = Set(controller.workspace.sessions.map(\.name))
            let sessionName = uniqueSessionName(baseName, existing: existingNames)
            saveToRecent(path)
            Task { @MainActor in
                await controller.addSession(name: sessionName, path: path)
                close()
            }
        }
    }

    // MARK: - Helpers

    private func isDirectory(_ path: String) -> Bool {
        guard !path.isEmpty else { return false }
        var isDir: ObjCBool = false
        return FileManager.default.fileExists(atPath: path, isDirectory: &isDir) && isDir.boolValue
    }

    /// Returns `base` if not in `existing`, otherwise appends a numeric suffix (base-2, base-3, …).
    private func uniqueSessionName(_ base: String, existing: Set<String>) -> String {
        guard existing.contains(base) else { return base }
        var counter = 2
        while existing.contains("\(base)-\(counter)") { counter += 1 }
        return "\(base)-\(counter)"
    }

    private func saveToRecent(_ path: String) {
        ForgeConfigStore.shared.update { config in
            config.recentDirectories.removeAll { $0 == path }
            config.recentDirectories.insert(path, at: 0)
            if config.recentDirectories.count > 20 {
                config.recentDirectories = Array(config.recentDirectories.prefix(20))
            }
            var counts = config.projectOpenCounts ?? [:]
            counts[path, default: 0] += 1
            config.projectOpenCounts = counts
        }
    }
}

struct ProjectRow: View {
    let path: String
    var openCount: Int = 0

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
            if openCount > 0 {
                Spacer()
                Text("\(openCount)")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .monospacedDigit()
            }
        }
        .textSelection(.disabled)
    }
}
