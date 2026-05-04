import SwiftUI

struct ProjectPickerView: View {
    var onDismiss: (() -> Void)? = nil
    @Environment(WorkspaceController.self) var controller
    @Environment(\.dismiss) var dismiss
    @State private var searchText = ""
    @State private var selectedPath: String?
    @State private var recentPaths: [String] = []
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Filter recent projects...", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(.title3)
                    .onSubmit { openProject() }
            }
            .padding(16)

            Divider()

            List(selection: $selectedPath) {
                let recentFiltered = displayRecent
                if !recentFiltered.isEmpty {
                    Section("Recent") {
                        ForEach(recentFiltered, id: \.self) { path in
                            ProjectRow(path: path)
                                .tag(path)
                        }
                    }
                }

                if !searchText.isEmpty && displayRecent.isEmpty {
                    VStack {
                        Spacer()
                        Text("No matches found")
                            .foregroundStyle(.secondary)
                            .font(.callout)
                            .frame(maxWidth: .infinity)
                        Spacer()
                    }
                    .frame(height: 200)
                    .listRowSeparator(.hidden)
                }
            }
            .listStyle(.plain)

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
            recentPaths = ForgeConfig.load().recentDirectories
        }
    }

    private func close() {
        if let onDismiss { onDismiss() } else { dismiss() }
    }

    // MARK: - Display

    private var displayRecent: [String] {
        if searchText.isEmpty { return recentPaths }
        let term = searchText.lowercased()
        return recentPaths.filter { path in
            guard !path.isEmpty else { return false }
            return path.lowercased().contains(term) ||
                URL(fileURLWithPath: path).lastPathComponent.lowercased().contains(term)
        }
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
        var config = ForgeConfig.load()
        config.recentDirectories.removeAll { $0 == path }
        config.recentDirectories.insert(path, at: 0)
        if config.recentDirectories.count > 20 {
            config.recentDirectories = Array(config.recentDirectories.prefix(20))
        }
        config.save()
    }
}

struct ProjectRow: View {
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
    }
}
