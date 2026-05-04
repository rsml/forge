import SwiftUI

struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralSettingsPane()
                .tabItem { Label("General", systemImage: "gearshape") }
            AppearanceSettingsPane()
                .tabItem { Label("Appearance", systemImage: "paintbrush") }
            KeyboardSettingsPane()
                .tabItem { Label("Keyboard", systemImage: "keyboard") }
            AboutPane()
                .tabItem { Label("About", systemImage: "info.circle") }
        }
        .frame(width: 560)
    }
}

// MARK: - General

private struct GeneralSettingsPane: View {
    @State private var config = ForgeConfig.load()

    private var general: Binding<ForgeConfig.GeneralSettings> {
        Binding(
            get: { config.general ?? ForgeConfig.GeneralSettings() },
            set: { config.general = $0; config.save() }
        )
    }

    var body: some View {
        Form {
            Section("Session") {
                Picker("Default shell", selection: Binding(
                    get: { general.wrappedValue.defaultShell ?? "zsh" },
                    set: { general.wrappedValue.defaultShell = $0; config.save() }
                )) {
                    Text("zsh").tag("zsh")
                    Text("bash").tag("bash")
                    Text("fish").tag("fish")
                }

                HStack {
                    Text("Default project directory")
                    Spacer()
                    Text(general.wrappedValue.defaultProjectDir ?? "~")
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Button("Choose…") {
                        pickDirectory()
                    }
                }
            }

            Section("Behavior") {
                Toggle("Auto-restore sessions on launch", isOn: Binding(
                    get: { general.wrappedValue.autoRestore ?? true },
                    set: { general.wrappedValue.autoRestore = $0; config.save() }
                ))

                Toggle("Confirm before closing", isOn: Binding(
                    get: { general.wrappedValue.confirmBeforeClose ?? true },
                    set: { general.wrappedValue.confirmBeforeClose = $0; config.save() }
                ))
            }
        }
        .formStyle(.grouped)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func pickDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Choose"
        if panel.runModal() == .OK, let url = panel.url {
            var g = general.wrappedValue
            g.defaultProjectDir = url.path
            config.general = g
            config.save()
        }
    }
}

// MARK: - Appearance

private struct AppearanceSettingsPane: View {
    @State private var config = ForgeConfig.load()

    private var appearance: Binding<ForgeConfig.AppearanceSettings> {
        Binding(
            get: { config.appearance ?? ForgeConfig.AppearanceSettings() },
            set: { config.appearance = $0; config.save() }
        )
    }

    var body: some View {
        Form {
            Section("Terminal Font") {
                HStack {
                    Text("Family")
                    Spacer()
                    TextField("e.g. Menlo", text: Binding(
                        get: { appearance.wrappedValue.fontFamily ?? "" },
                        set: { appearance.wrappedValue.fontFamily = $0.isEmpty ? nil : $0; config.save() }
                    ))
                    .multilineTextAlignment(.trailing)
                    .frame(width: 180)
                }

                HStack {
                    Text("Size")
                    Spacer()
                    Stepper(
                        value: Binding(
                            get: { appearance.wrappedValue.fontSize ?? 13 },
                            set: { appearance.wrappedValue.fontSize = $0; config.save() }
                        ),
                        in: 9...24
                    ) {
                        Text("\(appearance.wrappedValue.fontSize ?? 13) pt")
                            .monospacedDigit()
                    }
                }

                // Live preview
                let family = appearance.wrappedValue.fontFamily ?? "Menlo"
                let size = CGFloat(appearance.wrappedValue.fontSize ?? 13)
                Text("The quick brown fox jumps over the lazy dog")
                    .font(.custom(family, size: size))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 4)
            }

            Section("Theme") {
                HStack {
                    Text("Theme source")
                    Spacer()
                    TextField("e.g. ghostty-seti", text: Binding(
                        get: { config.theme?.source ?? "" },
                        set: { config.theme = ForgeConfig.ThemeConfig(source: $0.isEmpty ? nil : $0); config.save() }
                    ))
                    .multilineTextAlignment(.trailing)
                    .frame(width: 180)
                }
            }

            Section("Layout") {
                Picker("Tab bar position", selection: Binding(
                    get: { appearance.wrappedValue.tabBarPosition ?? "top" },
                    set: { appearance.wrappedValue.tabBarPosition = $0; config.save() }
                )) {
                    Text("Top").tag("top")
                    Text("Bottom").tag("bottom")
                }
                .pickerStyle(.segmented)
            }
        }
        .formStyle(.grouped)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Keyboard

private struct KeyboardSettingsPane: View {
    @State private var config = ForgeConfig.load()

    private var shortcutsBinding: Binding<[String: ForgeConfig.ShortcutConfig]> {
        Binding(
            get: { config.shortcuts ?? [:] },
            set: { config.shortcuts = $0.isEmpty ? nil : $0; config.save() }
        )
    }

    var body: some View {
        Form {
            Section("Shortcuts") {
                ShortcutEditor(shortcuts: shortcutsBinding)
            }
        }
        .formStyle(.grouped)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - About

private struct AboutPane: View {
    private var version: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev"
    }
    private var build: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "0"
    }

    var body: some View {
        VStack(spacing: 20) {
            Spacer()

            Image(systemName: "terminal.fill")
                .font(.system(size: 56))
                .foregroundStyle(Color.accentColor)

            VStack(spacing: 4) {
                Text("Forge")
                    .font(.title.bold())
                Text("Version \(version) (\(build))")
                    .foregroundStyle(.secondary)
                    .font(.subheadline)
            }

            Text("A native macOS frontend for tmux.")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Link("View on GitHub", destination: URL(string: "https://github.com/anthropics/forge")!)
                .font(.callout)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
}
