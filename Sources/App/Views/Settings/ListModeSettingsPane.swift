import SwiftUI

struct ListModeSettingsPane: View {
    private var store: ForgeConfigStore { .shared }

    var body: some View {
        Form {
            Section {
                Text("List mode shows sessions in a sidebar with tabbed windows — the default layout for managing multiple projects side by side.")
                    .foregroundStyle(.secondary)
                    .font(.callout)
            }

            Section("Layout") {
                Picker("Sidebar position", selection: generalBinding(\.sidebarPosition, default: "left")) {
                    Text("Left").tag("left")
                    Text("Right").tag("right")
                }
                .pickerStyle(.segmented)

                Picker("Tab bar position", selection: generalBinding(\.tabBarPosition, default: "top")) {
                    Text("Top").tag("top")
                    Text("Bottom").tag("bottom")
                }
                .pickerStyle(.segmented)
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
}
