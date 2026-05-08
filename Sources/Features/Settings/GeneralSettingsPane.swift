import SwiftUI
import ForgeCore

struct GeneralSettingsPane: View {
    private var store: ForgeConfigStore { .shared }

    var body: some View {
        Form {
            Section("Project") {
                Picker("Default shell", selection: generalBinding(\.defaultShell, default: "zsh")) {
                    Text("zsh").tag("zsh")
                    Text("bash").tag("bash")
                    Text("fish").tag("fish")
                }

                HStack {
                    Text("Default project directory")
                    Spacer()
                    Text(store.config.general?.defaultProjectDir ?? "~")
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Button("Choose...") { pickDirectory() }
                }
            }

            Section("Behavior") {
                Toggle("Auto-restore sessions on launch", isOn: generalBinding(\.autoRestore, default: true))
                Toggle("Warn before closing Forge", isOn: generalBinding(\.confirmBeforeClose, default: true))
                Toggle("Warn before closing a project", isOn: generalBinding(\.warnOnCloseProject, default: true))
                Toggle("Warn before closing a tab", isOn: generalBinding(\.warnOnCloseTab, default: false))
                Toggle("Confirm before moving a tab between projects", isOn: generalBinding(\.warnOnMoveTab, default: true))
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
