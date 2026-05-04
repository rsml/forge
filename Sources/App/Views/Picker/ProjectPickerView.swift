import SwiftUI

struct ProjectPickerView: View {
    @Environment(WorkspaceController.self) var controller
    @Environment(\.dismiss) var dismiss
    @State private var searchText = ""
    @State private var selectedPath: String?
    @State private var recentPaths: [String] = []
    @State private var searchResults: [String] = []
    @State private var searchTask: Task<Void, Never>?
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search for a project folder...", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(.title3)
                    .onSubmit { openProject() }
                    .onChange(of: searchText) { _, newValue in
                        scheduleSearch(newValue)
                    }
            }
            .padding(16)

            Divider()

            List(selection: $selectedPath) {
                // Currently open projects
                let openPaths = controller.workspace.sessions.compactMap(\.path)
                if !openPaths.isEmpty && searchText.isEmpty {
                    Section("Open Projects") {
                        ForEach(openPaths, id: \.self) { path in
                            ProjectRow(path: path)
                                .tag(path)
                        }
                    }
                }

                // Recent (not currently open)
                let recentFiltered = displayRecent.filter { !openPaths.contains($0) }
                if !recentFiltered.isEmpty {
                    Section("Recent") {
                        ForEach(recentFiltered, id: \.self) { path in
                            ProjectRow(path: path)
                                .tag(path)
                        }
                    }
                }

                // Filesystem search results
                if !searchResults.isEmpty {
                    Section("Found on Disk") {
                        ForEach(searchResults, id: \.self) { path in
                            ProjectRow(path: path)
                                .tag(path)
                        }
                    }
                }

                if !searchText.isEmpty && displayRecent.isEmpty && searchResults.isEmpty {
                    HStack {
                        Spacer()
                        Text("No matches found")
                            .foregroundStyle(.secondary)
                            .font(.callout)
                        Spacer()
                    }
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
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Open") { openProject() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(resolvedPath == nil)
            }
            .padding(16)
        }
        .frame(width: 520, height: 440)
        .onAppear {
            recentPaths = ForgeConfig.load().recentDirectories
        }
    }

    // MARK: - Display

    private var displayRecent: [String] {
        if searchText.isEmpty { return recentPaths }
        let term = searchText.lowercased()
        return recentPaths.filter {
            $0.lowercased().contains(term) ||
            URL(fileURLWithPath: $0).lastPathComponent.lowercased().contains(term)
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
        errorMessage = nil
        saveToRecent(path)
        Task {
            await controller.addSession(name: URL(fileURLWithPath: path).lastPathComponent, path: path)
            dismiss()
        }
    }

    private func browseForFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.message = "Choose a project directory"
        if panel.runModal() == .OK, let url = panel.url {
            selectedPath = url.path
            searchText = url.lastPathComponent
        }
    }

    // MARK: - Filesystem Search

    private func scheduleSearch(_ query: String) {
        errorMessage = nil
        searchTask?.cancel()
        guard !query.isEmpty else {
            searchResults = []
            return
        }
        searchTask = Task {
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled else { return }
            let results = await findDirectories(matching: query)
            guard !Task.isCancelled else { return }
            searchResults = results
        }
    }

    private func findDirectories(matching query: String) async -> [String] {
        let expanded = (query as NSString).expandingTildeInPath
        // If user typed an absolute path, check if it exists directly
        if expanded.hasPrefix("/") && isDirectory(expanded) {
            return [expanded]
        }

        // Search common project roots
        let searchRoots = projectSearchRoots()
        let term = query.lowercased()
        var found: [String] = []
        let fm = FileManager.default

        for root in searchRoots {
            guard let entries = try? fm.contentsOfDirectory(atPath: root) else { continue }
            for entry in entries where entry.lowercased().contains(term) {
                let full = (root as NSString).appendingPathComponent(entry)
                var isDir: ObjCBool = false
                if fm.fileExists(atPath: full, isDirectory: &isDir), isDir.boolValue {
                    // Prefer directories with .git (actual projects)
                    found.append(full)
                }
                if found.count >= 20 { return found }
            }
            if Task.isCancelled { return [] }
        }

        // Sort: git repos first, then alphabetical
        let fm2 = FileManager.default
        return found.sorted { a, b in
            let aGit = fm2.fileExists(atPath: (a as NSString).appendingPathComponent(".git"))
            let bGit = fm2.fileExists(atPath: (b as NSString).appendingPathComponent(".git"))
            if aGit != bGit { return aGit }
            return a.localizedCaseInsensitiveCompare(b) == .orderedAscending
        }
    }

    private func projectSearchRoots() -> [String] {
        let home = NSHomeDirectory()
        let candidates = [
            "\(home)/Projects",
            "\(home)/Developer",
            "\(home)/Code",
            "\(home)/src",
            "\(home)/repos",
            "\(home)/Personal",
            "\(home)/Work",
            "\(home)/Documents",
            "\(home)/Desktop",
        ]
        return candidates.filter { isDirectory($0) }
    }

    // MARK: - Helpers

    private func isDirectory(_ path: String) -> Bool {
        var isDir: ObjCBool = false
        return FileManager.default.fileExists(atPath: path, isDirectory: &isDir) && isDir.boolValue
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

    private var name: String { URL(fileURLWithPath: path).lastPathComponent }
    private var displayPath: String { path.replacingOccurrences(of: NSHomeDirectory(), with: "~") }
    private var isGitRepo: Bool { FileManager.default.fileExists(atPath: (path as NSString).appendingPathComponent(".git")) }

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
