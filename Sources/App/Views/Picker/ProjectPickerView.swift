import SwiftUI

struct ProjectPickerView: View {
    @Environment(WorkspaceController.self) var controller
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
                    .onSubmit { openProject() }
            }
            .padding(16)

            Divider()

            List(selection: $selectedPath) {
                if !filteredPaths.isEmpty {
                    Section("Recent Projects") {
                        ForEach(filteredPaths, id: \.self) { path in
                            HStack {
                                Image(systemName: "folder").foregroundStyle(.secondary)
                                VStack(alignment: .leading) {
                                    Text(URL(fileURLWithPath: path).lastPathComponent)
                                    Text(path).font(.caption).foregroundStyle(.secondary)
                                }
                            }
                            .tag(path)
                        }
                    }
                }
            }
            .listStyle(.plain)

            Divider()

            HStack {
                Button("Browse...") { browseForFolder() }
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Open") { openProject() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(selectedPath == nil && searchText.isEmpty)
            }
            .padding(16)
        }
        .frame(width: 500, height: 400)
        .onAppear { recentPaths = ForgeConfig.load().recentDirectories }
    }

    private var filteredPaths: [String] {
        searchText.isEmpty ? recentPaths : recentPaths.filter { $0.localizedCaseInsensitiveContains(searchText) }
    }

    private func openProject() {
        let path = selectedPath ?? searchText
        guard !path.isEmpty else { return }
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
}
