import SwiftUI

struct TerminalSettingsPane: View {
    private var store: ForgeConfigStore { .shared }

    private var fontFamily: String { store.config.terminal?.fontFamily ?? store.config.appearance?.fontFamily ?? "" }
    private var fontSize: Int { store.config.terminal?.fontSize ?? store.config.appearance?.fontSize ?? 13 }
    private var scrollbackLines: Int { store.config.terminal?.scrollbackLines ?? 50000 }

    @State private var scrollbackText = ""

    private static let monoFonts: [String] = {
        let fm = NSFontManager.shared
        var families: [String] = []
        for family in fm.availableFontFamilies {
            if let members = fm.availableMembers(ofFontFamily: family),
               let first = members.first,
               let traits = first[3] as? UInt,
               (traits & UInt(NSFontTraitMask.fixedPitchFontMask.rawValue)) != 0 {
                families.append(family)
            }
        }
        // Also include well-known mono fonts that might not have the trait set
        let known = ["Menlo", "Monaco", "SF Mono", "Courier New", "Dank Mono",
                     "JetBrains Mono", "JetBrainsMono Nerd Font", "Fira Code",
                     "FiraCode Nerd Font", "MesloLGS NF", "Hack Nerd Font",
                     "Source Code Pro", "IBM Plex Mono"]
        for name in known {
            if !families.contains(name), NSFont(name: name, size: 13) != nil {
                families.append(name)
            }
        }
        return families.sorted()
    }()

    var body: some View {
        Form {
            Section("Font") {
                Picker("Family", selection: Binding(
                    get: { fontFamily.isEmpty ? "Menlo" : fontFamily },
                    set: { newValue in
                        store.update {
                            if $0.terminal == nil { $0.terminal = ForgeConfig.TerminalSettings() }
                            $0.terminal!.fontFamily = newValue
                        }
                    }
                )) {
                    ForEach(Self.monoFonts, id: \.self) { name in
                        Text(name).tag(name)
                    }
                }

                HStack {
                    Text("Size")
                    Spacer()
                    TextField("", value: Binding(
                        get: { fontSize },
                        set: { newValue in
                            let clamped = min(max(newValue, 9), 36)
                            store.update {
                                if $0.terminal == nil { $0.terminal = ForgeConfig.TerminalSettings() }
                                $0.terminal!.fontSize = clamped
                            }
                        }
                    ), format: .number)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 50)

                    Stepper("", value: Binding(
                        get: { fontSize },
                        set: { newValue in
                            store.update {
                                if $0.terminal == nil { $0.terminal = ForgeConfig.TerminalSettings() }
                                $0.terminal!.fontSize = newValue
                            }
                        }
                    ), in: 9...36)
                    .labelsHidden()
                }

                // Live preview
                let family = fontFamily.isEmpty ? "Menlo" : fontFamily
                let size = CGFloat(fontSize)
                Text("The quick brown fox jumps over the lazy dog")
                    .font(.custom(family, size: size))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 4)
            }

            Section("Terminal") {
                HStack {
                    Text("Scrollback lines")
                    Spacer()
                    TextField("", text: $scrollbackText)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 80)
                        .onSubmit { commitScrollback() }
                        .onChange(of: scrollbackText) { _, newValue in
                            // Allow only digits
                            let filtered = newValue.filter(\.isNumber)
                            if filtered != newValue { scrollbackText = filtered }
                        }

                    Stepper("", value: Binding(
                        get: { scrollbackLines },
                        set: { newValue in
                            store.update {
                                if $0.terminal == nil { $0.terminal = ForgeConfig.TerminalSettings() }
                                $0.terminal!.scrollbackLines = newValue
                            }
                            scrollbackText = "\(newValue)"
                        }
                    ), in: 1000...500_000, step: 5000)
                    .labelsHidden()
                }

                Picker("Tab bar position", selection: Binding(
                    get: { store.config.terminal?.tabBarPosition ?? store.config.appearance?.tabBarPosition ?? "top" },
                    set: { newValue in
                        store.update {
                            if $0.terminal == nil { $0.terminal = ForgeConfig.TerminalSettings() }
                            $0.terminal!.tabBarPosition = newValue
                        }
                    }
                )) {
                    Text("Top").tag("top")
                    Text("Bottom").tag("bottom")
                }
                .pickerStyle(.segmented)

                Toggle("Use tmux for session persistence", isOn: Binding(
                    get: { store.config.terminal?.useTmuxPersistence ?? true },
                    set: { newValue in
                        store.update {
                            if $0.terminal == nil { $0.terminal = ForgeConfig.TerminalSettings() }
                            $0.terminal!.useTmuxPersistence = newValue
                        }
                    }
                ))
            }

            Section("tmux Configuration") {
                TextEditor(text: Binding(
                    get: { store.config.terminal?.tmuxConfigOverride ?? Self.defaultTmuxConfig },
                    set: { newValue in
                        store.update {
                            if $0.terminal == nil { $0.terminal = ForgeConfig.TerminalSettings() }
                            $0.terminal!.tmuxConfigOverride = newValue
                        }
                    }
                ))
                .font(.system(.body, design: .monospaced))
                .frame(height: 80)
                .scrollContentBackground(.hidden)
                .padding(4)
                .background(Color(nsColor: .controlBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 6))

                HStack {
                    Spacer()
                    Button("Reset to Defaults") {
                        store.update { $0.terminal?.tmuxConfigOverride = nil }
                    }
                    .foregroundStyle(.red)
                }
            }
        }
        .formStyle(.grouped)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear { scrollbackText = "\(scrollbackLines)" }
    }

    private func commitScrollback() {
        guard let value = Int(scrollbackText), value >= 1000 else {
            scrollbackText = "\(scrollbackLines)"
            return
        }
        store.update {
            if $0.terminal == nil { $0.terminal = ForgeConfig.TerminalSettings() }
            $0.terminal!.scrollbackLines = value
        }
    }

    static let defaultTmuxConfig = """
    set -g status off
    set -g mouse on
    set -g default-terminal "xterm-256color"
    """
}
