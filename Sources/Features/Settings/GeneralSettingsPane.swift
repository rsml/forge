import SwiftUI
import ForgeCore

struct GeneralSettingsPane: View {
    private var store: ForgeConfigStore { .shared }

    var body: some View {
        Form {
            Section("Startup") {
                LabeledContent("Default directory") {
                    Text(store.config.general?.defaultProjectDir ?? "~")
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Button("Choose...") { pickDirectory() }
                }
                .padding(.vertical, -4)
                Toggle("Restore sessions on launch", isOn: generalBinding(\.autoRestore, default: true))
                    .padding(.vertical, -4)
            }

            Section("Confirmations") {
                Toggle("Warn before closing Forge", isOn: generalBinding(\.confirmBeforeClose, default: true))
                    .padding(.vertical, -4)
                Picker("Confirm project close", selection: generalBinding(\.confirmCloseProject, default: "whenActive")) {
                    Text("Never").tag("never")
                    Text("When a process is running").tag("whenActive")
                    Text("Always").tag("always")
                }
                .padding(.vertical, -4)
                Picker("Confirm tab close", selection: generalBinding(\.confirmCloseTab, default: "whenActive")) {
                    Text("Never").tag("never")
                    Text("When a process is running").tag("whenActive")
                    Text("Always").tag("always")
                }
                .padding(.vertical, -4)
                Picker("Confirm pane close", selection: generalBinding(\.confirmClosePane, default: "whenActive")) {
                    Text("Never").tag("never")
                    Text("When a process is running").tag("whenActive")
                    Text("Always").tag("always")
                }
                .padding(.vertical, -4)
            }
        }
        .formStyle(.grouped)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func generalBinding<T>(_ keyPath: WritableKeyPath<ForgeConfig.GeneralSettings, T?>, default defaultValue: T) -> Binding<T> {
        Binding(
            get: { store.config.general?[keyPath: keyPath] ?? defaultValue },
            set: { newValue in
                store.update { config in
                    if config.general == nil { config.general = ForgeConfig.GeneralSettings() }
                    config.general![keyPath: keyPath] = newValue
                }
            }
        )
    }

    private func pickDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Choose"
        if let currentDir = store.config.general?.defaultProjectDir {
            panel.directoryURL = URL(fileURLWithPath: currentDir)
        } else {
            panel.directoryURL = URL(fileURLWithPath: NSHomeDirectory())
        }
        if panel.runModal() == .OK, let url = panel.url {
            store.update {
                if $0.general == nil { $0.general = ForgeConfig.GeneralSettings() }
                $0.general!.defaultProjectDir = url.path
            }
        }
    }
}
