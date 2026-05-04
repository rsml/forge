import SwiftUI

// MARK: - Data model

struct ShortcutEntry: Identifiable {
    let id: String           // stable key used in ForgeConfig.shortcuts
    let label: String
    let category: String
    let defaultHint: String  // built-in default, e.g. "⌘P"
    var currentHint: String  // may be overridden
}

// MARK: - Shortcut Editor (full section view)

struct ShortcutEditor: View {
    @Binding var shortcuts: [String: ForgeConfig.ShortcutConfig]

    @State private var entries: [ShortcutEntry] = []
    @State private var recordingId: String? = nil
    @State private var captureSession = KeyCaptureSession()
    @State private var conflicts: Set<String> = []

    private let categories = ["File", "View", "Splits", "Tabs", "Projects", "App"]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(categories, id: \.self) { category in
                let group = entries.filter { $0.category == category }
                if !group.isEmpty {
                    Section(category) {
                        ForEach(group) { entry in
                            shortcutRow(entry)
                        }
                    }
                }
            }

            Divider().padding(.vertical, 8)

            HStack {
                Spacer()
                Button("Reset All to Defaults") {
                    resetAll()
                }
                .foregroundStyle(.red)
            }
        }
        .onAppear { buildEntries() }
        .onChange(of: shortcuts) { buildEntries() }
    }

    // MARK: - Row

    @ViewBuilder
    private func shortcutRow(_ entry: ShortcutEntry) -> some View {
        HStack {
            Text(entry.label)
                .frame(maxWidth: .infinity, alignment: .leading)

            if conflicts.contains(entry.id) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.yellow)
                    .font(.system(size: 12))
                    .help("Conflicts with another shortcut")
            }

            ShortcutRecorder(
                current: entry.currentHint,
                isRecording: recordingId == entry.id,
                onStartRecording: { startRecording(entry) },
                onCancel: { stopRecording() }
            )

            Button {
                resetEntry(entry)
            } label: {
                Text("Reset")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .opacity(shortcuts[entry.id] != nil ? 1 : 0.4)
            .disabled(shortcuts[entry.id] == nil)
        }
        .padding(.vertical, 2)
    }

    // MARK: - Recording

    private func startRecording(_ entry: ShortcutEntry) {
        stopRecording()
        recordingId = entry.id
        captureSession.start { result in
            DispatchQueue.main.async {
                if let r = result {
                    shortcuts[entry.id] = ForgeConfig.ShortcutConfig(key: r.key, modifiers: r.modifiers)
                }
                recordingId = nil
                buildEntries()
                detectConflicts()
            }
        }
    }

    private func stopRecording() {
        captureSession.stop()
        recordingId = nil
    }

    // MARK: - Reset

    private func resetEntry(_ entry: ShortcutEntry) {
        shortcuts.removeValue(forKey: entry.id)
        buildEntries()
        detectConflicts()
    }

    private func resetAll() {
        shortcuts.removeAll()
        buildEntries()
        detectConflicts()
    }

    // MARK: - Build entries from static defaults

    private func buildEntries() {
        let defaults = Self.defaultEntries
        entries = defaults.map { d in
            var entry = d
            if let override = shortcuts[d.id] {
                entry.currentHint = Self.hint(from: override)
            }
            return entry
        }
        detectConflicts()
    }

    private func detectConflicts() {
        var seen: [String: String] = [:]  // hint → id
        var found: Set<String> = []
        for entry in entries {
            let h = entry.currentHint
            if let existing = seen[h] {
                found.insert(existing)
                found.insert(entry.id)
            } else {
                seen[h] = entry.id
            }
        }
        conflicts = found
    }

    // MARK: - Helpers

    private static func hint(from config: ForgeConfig.ShortcutConfig) -> String {
        var s = ""
        if config.modifiers.contains("control") { s += "⌃" }
        if config.modifiers.contains("option")  { s += "⌥" }
        if config.modifiers.contains("shift")   { s += "⇧" }
        if config.modifiers.contains("command") { s += "⌘" }
        s += config.key.uppercased()
        return s
    }

    // MARK: - Default shortcut table (mirrors KeyboardShortcuts enum)

    static let defaultEntries: [ShortcutEntry] = [
        // File
        .init(id: "newProject",    label: "New Project",       category: "File",     defaultHint: "⌘N",  currentHint: "⌘N"),
        .init(id: "newTab",        label: "New Tab",           category: "File",     defaultHint: "⌘T",  currentHint: "⌘T"),
        .init(id: "closePane",     label: "Close Pane",        category: "File",     defaultHint: "⌘W",  currentHint: "⌘W"),
        .init(id: "closeProject",  label: "Close Project",     category: "File",     defaultHint: "⇧⌘W", currentHint: "⇧⌘W"),
        // View
        .init(id: "toggleSidebar", label: "Toggle Sidebar",    category: "View",     defaultHint: "⌘B",  currentHint: "⌘B"),
        .init(id: "commandPalette",label: "Command Palette",   category: "View",     defaultHint: "⌘P",  currentHint: "⌘P"),
        .init(id: "notifications", label: "Notifications",     category: "View",     defaultHint: "⇧⌘N", currentHint: "⇧⌘N"),
        // Splits
        .init(id: "splitHorizontal", label: "Split Horizontally", category: "Splits", defaultHint: "⌘D",  currentHint: "⌘D"),
        .init(id: "splitVertical",   label: "Split Vertically",   category: "Splits", defaultHint: "⇧⌘D", currentHint: "⇧⌘D"),
        // Tabs
        .init(id: "selectTabLeft",  label: "Select Tab Left",   category: "Tabs", defaultHint: "⇧⌘[", currentHint: "⇧⌘["),
        .init(id: "selectTabRight", label: "Select Tab Right",  category: "Tabs", defaultHint: "⇧⌘]", currentHint: "⇧⌘]"),
        .init(id: "moveTabLeft",    label: "Move Tab Left",     category: "Tabs", defaultHint: "⇧⌘←", currentHint: "⇧⌘←"),
        .init(id: "moveTabRight",   label: "Move Tab Right",    category: "Tabs", defaultHint: "⇧⌘→", currentHint: "⇧⌘→"),
        // Projects
        .init(id: "nextProject",    label: "Next Project",      category: "Projects", defaultHint: "⌃⇥", currentHint: "⌃⇥"),
        .init(id: "prevProject",    label: "Previous Project",  category: "Projects", defaultHint: "⌃⇧⇥", currentHint: "⌃⇧⇥"),
        // App
        .init(id: "settings",      label: "Settings",          category: "App", defaultHint: "⌘,", currentHint: "⌘,"),
    ]
}
