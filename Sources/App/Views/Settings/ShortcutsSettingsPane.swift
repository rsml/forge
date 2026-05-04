import SwiftUI

struct ShortcutsSettingsPane: View {
    private var store: ForgeConfigStore { .shared }
    @State private var recordingId: String?
    @State private var captureSession = KeyCaptureSession()
    @State private var conflicts: Set<String> = []

    private let categories = ["File", "View", "Splits", "Tabs", "Projects", "App"]

    private var shortcuts: [String: ForgeConfig.ShortcutConfig] {
        store.config.shortcuts ?? [:]
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                ForEach(categories, id: \.self) { category in
                    let group = KeyboardShortcuts.allDefaults.filter { $0.category == category }
                    if !group.isEmpty {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(category)
                                .font(.headline)
                                .padding(.bottom, 4)

                            LazyVGrid(columns: [
                                GridItem(.flexible(), alignment: .leading),
                                GridItem(.fixed(200), alignment: .trailing),
                            ], spacing: 6) {
                                ForEach(group, id: \.id) { entry in
                                    Text(entry.shortcut.label)

                                    HStack(spacing: 6) {
                                        let currentHint = resolveHint(id: entry.id, default: entry.shortcut)
                                        ShortcutRecorder(
                                            current: currentHint,
                                            isRecording: recordingId == entry.id,
                                            onStartRecording: { startRecording(entry.id) },
                                            onCancel: { stopRecording() }
                                        )

                                        if conflicts.contains(entry.id) {
                                            Image(systemName: "exclamationmark.triangle.fill")
                                                .foregroundStyle(.yellow)
                                                .font(.system(size: 12))
                                                .help("Conflicts with another shortcut")
                                        }

                                        Button {
                                            store.update { $0.shortcuts?.removeValue(forKey: entry.id) }
                                            detectConflicts()
                                        } label: {
                                            Image(systemName: "xmark.circle.fill")
                                                .foregroundStyle(.secondary)
                                                .font(.system(size: 14))
                                        }
                                        .buttonStyle(.plain)
                                        .opacity(shortcuts[entry.id] != nil ? 1 : 0.3)
                                        .disabled(shortcuts[entry.id] == nil)
                                    }
                                }
                            }
                        }
                    }
                }

                Divider()

                HStack {
                    Spacer()
                    Button("Reset All to Defaults") {
                        store.update { $0.shortcuts = nil }
                        detectConflicts()
                    }
                    .foregroundStyle(.red)
                }
            }
            .padding(20)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear { detectConflicts() }
    }

    private func resolveHint(id: String, default shortcut: Shortcut) -> String {
        if let override = shortcuts[id] {
            return Shortcut(from: override, label: "").hint
        }
        return shortcut.hint
    }

    private func startRecording(_ id: String) {
        stopRecording()
        recordingId = id
        captureSession.start { result in
            DispatchQueue.main.async {
                if let r = result {
                    store.update {
                        if $0.shortcuts == nil { $0.shortcuts = [:] }
                        $0.shortcuts![id] = ForgeConfig.ShortcutConfig(key: r.key, modifiers: r.modifiers)
                    }
                }
                recordingId = nil
                detectConflicts()
            }
        }
    }

    private func stopRecording() {
        captureSession.stop()
        recordingId = nil
    }

    private func detectConflicts() {
        var seen: [String: String] = [:]
        var found: Set<String> = []
        for entry in KeyboardShortcuts.allDefaults {
            let hint = resolveHint(id: entry.id, default: entry.shortcut)
            if let existing = seen[hint] {
                found.insert(existing)
                found.insert(entry.id)
            } else {
                seen[hint] = entry.id
            }
        }
        conflicts = found
    }
}
