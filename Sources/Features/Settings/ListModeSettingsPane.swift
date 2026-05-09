import SwiftUI
import ForgeCore

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

            Section("Tab Highlight") {
                Picker("Highlight color", selection: generalBinding(\.tabHighlightColorMode, default: "accent")) {
                    Text("macOS Accent Color").tag("accent")
                    Text("Theme Accent Color").tag("theme")
                    Text("Custom").tag("custom")
                }

                if (store.config.general?.tabHighlightColorMode ?? "accent") == "custom" {
                    ColorPicker("Custom color", selection: customColorBinding, supportsOpacity: true)
                        .alignmentGuide(.firstTextBaseline) { d in d[VerticalAlignment.center] }
                }

                LabeledContent("Preview") {
                    let tabsOnBottom = (store.config.general?.tabBarPosition ?? "top") == "bottom"
                    RoundedRectangle(cornerRadius: 4)
                        .fill(store.resolvedTheme?.background.color ?? Color(red: 0.1, green: 0.1, blue: 0.1))
                        .frame(width: 48, height: 24)
                        .overlay(alignment: tabsOnBottom ? .top : .bottom) {
                            RoundedRectangle(cornerRadius: 1)
                                .fill(store.tabHighlightColor.opacity(0.6))
                                .frame(height: 2)
                        }
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                        .alignmentGuide(.firstTextBaseline) { d in d[VerticalAlignment.center] }
                }
            }
        }
        .formStyle(.grouped)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var customColorBinding: Binding<Color> {
        Binding(
            get: {
                if let hex = store.config.general?.tabHighlightCustomColor {
                    return Color(hex: hex)
                }
                return Color.accentColor
            },
            set: { newColor in
                let hex = newColor.hexString
                store.update { config in
                    if config.general == nil { config.general = ForgeConfig.GeneralSettings() }
                    config.general!.tabHighlightCustomColor = hex
                }
            }
        )
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
