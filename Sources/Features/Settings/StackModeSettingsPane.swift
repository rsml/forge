import SwiftUI
import ForgeCore

struct StackModeSettingsPane: View {
    private var store: ForgeConfigStore { .shared }

    var body: some View {
        Form {
            Section {
                Text("Stack mode displays sessions as a single vertical stack without a sidebar — focused on one project at a time.")
                    .foregroundStyle(.secondary)
                    .font(.callout)
            }

            Section("Layout") {
                Picker("Toolbar position", selection: stackBinding(\.toolbarPosition, default: "bottom")) {
                    Text("Top").tag("top")
                    Text("Bottom").tag("bottom")
                }
                .pickerStyle(.segmented)
                .padding(.vertical, -4)
            }

            Section("Attention") {
                Picker("Bring to foreground", selection: stackBinding(\.bringToForeground, default: "never")) {
                    Text("Never").tag("never")
                    Text("Always").tag("always")
                }
                .padding(.vertical, -4)

                Picker("Notify", selection: stackBinding(\.notify, default: "never")) {
                    Text("Never").tag("never")
                    Text("Always").tag("always")
                }
                .padding(.vertical, -4)

                Toggle(isOn: stackBinding(\.notifyInStackMode, default: false)) {
                    Text("Show notifications in stack mode")
                    Text("Recommended off. Stack mode always shows tabs that need attention in order, so notifications are usually unnecessary.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, -4)
            }
        }
        .formStyle(.grouped)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func stackBinding<T>(_ keyPath: WritableKeyPath<ForgeConfig.StackViewSettings, T?>, default defaultValue: T) -> Binding<T> {
        Binding(
            get: { store.config.stackView?[keyPath: keyPath] ?? defaultValue },
            set: { newValue in
                store.update { config in
                    if config.stackView == nil { config.stackView = ForgeConfig.StackViewSettings() }
                    config.stackView![keyPath: keyPath] = newValue
                }
            }
        )
    }
}
