import SwiftUI

struct ShortcutsSettingsPane: View {
    private var store: ForgeConfigStore { .shared }
    @State private var recordingId: String?
    @State private var captureSession = KeyCaptureSession()
    @State private var conflicts: Set<String> = []

    private var shortcuts: [String: ForgeConfig.ShortcutConfig] {
        store.config.shortcuts ?? [:]
    }

    var body: some View {
        ScrollView {
            HStack(alignment: .top, spacing: 24) {
                VStack(alignment: .leading, spacing: 24) {
                    categorySection("App")
                    categorySection("File")
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                VStack(alignment: .leading, spacing: 24) {
                    categorySection("View")
                    categorySection("Splits")
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                VStack(alignment: .leading, spacing: 24) {
                    categorySection("Tabs")
                    categorySection("Projects")
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(20)

            Divider().padding(.horizontal, 20)

            HStack {
                Spacer()
                Button("Reset All to Defaults") {
                    store.update { $0.shortcuts = nil }
                    detectConflicts()
                }
                .foregroundStyle(.red)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 12)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear { detectConflicts() }
    }

    @ViewBuilder
    private func categorySection(_ category: String) -> some View {
        let group = KeyboardShortcuts.allDefaults.filter { $0.category == category }
        if !group.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text(category.uppercased())
                    .font(.system(size: 11, weight: .semibold))
                    .tracking(1.2)
                    .foregroundStyle(.secondary)
                    .padding(.bottom, 2)

                ForEach(group, id: \.id) { entry in
                    HStack(spacing: 0) {
                        Text(entry.shortcut.label)
                            .font(.system(size: 13))
                            .frame(maxWidth: .infinity, alignment: .leading)

                        HStack(spacing: 8) {
                            if conflicts.contains(entry.id) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundStyle(.yellow)
                                    .font(.system(size: 12))
                                    .help("Conflicts with another shortcut")
                            }

                            ShortcutRecorder(
                                current: resolveHint(id: entry.id, default: entry.shortcut),
                                isRecording: recordingId == entry.id,
                                onStartRecording: { startRecording(entry.id) },
                                onCancel: { stopRecording() }
                            )

                            Button {
                                store.update { $0.shortcuts?.removeValue(forKey: entry.id) }
                                detectConflicts()
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(.tertiary)
                                    .font(.system(size: 14))
                            }
                            .buttonStyle(.plain)
                            .opacity(shortcuts[entry.id] != nil ? 1 : 0.3)
                            .disabled(shortcuts[entry.id] == nil)
                        }
                    }
                    .padding(.vertical, 3)
                }
            }
        }
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
