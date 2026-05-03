import SwiftUI

struct ProjectPickerView: View {
    @Environment(TmuxController.self) var tmux
    @Environment(\.dismiss) var dismiss
    @State private var searchText = ""
    @State private var selectedPath: String?
    @State private var recentPaths: [String] = []

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)

                TextField("Search or enter project path...", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(.title3)
                    .onSubmit {
                        openProject()
                    }
            }
            .padding(16)

            Divider()

            List(selection: $selectedPath) {
                if !filteredPaths.isEmpty {
                    Section("Recent Projects") {
                        ForEach(filteredPaths, id: \.self) { path in
                            HStack {
                                Image(systemName: "folder")
                                    .foregroundStyle(.secondary)

                                VStack(alignment: .leading) {
                                    Text(URL(fileURLWithPath: path).lastPathComponent)
                                        .font(.body)

                                    Text(path)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .tag(path)
                        }
                    }
                }

                let unattachedSessions = tmux.state.sessions.filter { !$0.attached }
                if !unattachedSessions.isEmpty {
                    Section("Unattached Sessions") {
                        ForEach(unattachedSessions) { session in
                            HStack {
                                StatusDot(status: session.aggregateStatus)

                                VStack(alignment: .leading) {
                                    Text(session.name)
                                        .font(.body)

                                    if let path = session.path {
                                        Text(path)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                            .tag(session.path ?? session.name)
                        }
                    }
                }
            }
            .listStyle(.plain)

            Divider()

            HStack {
                Button("Browse...") {
                    browseForFolder()
                }

                Spacer()

                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Button("Open") {
                    openProject()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(selectedPath == nil && searchText.isEmpty)
            }
            .padding(16)
        }
        .frame(width: 500, height: 400)
        .onAppear {
            loadRecentPaths()
        }
    }

    private var filteredPaths: [String] {
        if searchText.isEmpty {
            return recentPaths
        }
        return recentPaths.filter {
            $0.localizedCaseInsensitiveContains(searchText)
        }
    }

    private func openProject() {
        let path = selectedPath ?? searchText
        guard !path.isEmpty else { return }

        let name = URL(fileURLWithPath: path).lastPathComponent
        Task {
            await tmux.newSession(name: name, path: path)
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

    private func loadRecentPaths() {
        let config = ForgeConfig.load()
        recentPaths = config.recentDirectories
    }
}

// MARK: - Config File Model

struct ForgeConfig: Codable {
    var projects: [ProjectConfig]
    var recentDirectories: [String]
    var theme: ThemeConfig?

    struct ProjectConfig: Codable {
        var name: String
        var path: String
        var color: String?
        var pinned: Bool?
        var sortOrder: Int?
    }

    struct ThemeConfig: Codable {
        var source: String?
    }

    static let defaultConfig = ForgeConfig(
        projects: [],
        recentDirectories: [],
        theme: ThemeConfig(source: "ghostty-seti")
    )

    static var configURL: URL {
        URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent(".config/forge/config.json")
    }

    static func load() -> ForgeConfig {
        guard let data = try? Data(contentsOf: configURL),
              let config = try? JSONDecoder().decode(ForgeConfig.self, from: data) else {
            return defaultConfig
        }
        return config
    }

    func save() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(self) else { return }

        let dir = ForgeConfig.configURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try? data.write(to: ForgeConfig.configURL)
    }
}
