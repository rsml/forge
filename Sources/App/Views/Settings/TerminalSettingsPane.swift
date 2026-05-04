import SwiftUI

struct TerminalSettingsPane: View {
    private var store: ForgeConfigStore { .shared }

    private var fontFamily: String { store.config.terminal?.fontFamily ?? store.config.appearance?.fontFamily ?? "" }
    private var fontSize: Int { store.config.terminal?.fontSize ?? store.config.appearance?.fontSize ?? 13 }

    var body: some View {
        Form {
            Section("Font") {
                HStack {
                    Text("Family")
                    Spacer()
                    TextField("e.g. Menlo", text: terminalBinding(\.fontFamily, default: ""))
                        .multilineTextAlignment(.trailing)
                        .frame(width: 180)
                }

                HStack {
                    Text("Size")
                    Spacer()
                    Stepper(
                        value: Binding(
                            get: { fontSize },
                            set: { newValue in
                                store.update {
                                    if $0.terminal == nil { $0.terminal = ForgeConfig.TerminalSettings() }
                                    $0.terminal!.fontSize = newValue
                                }
                            }
                        ),
                        in: 9...24
                    ) {
                        Text("\(fontSize) pt")
                            .monospacedDigit()
                    }
                }

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
                    Stepper(
                        value: Binding(
                            get: { store.config.terminal?.scrollbackLines ?? 50000 },
                            set: { newValue in
                                store.update {
                                    if $0.terminal == nil { $0.terminal = ForgeConfig.TerminalSettings() }
                                    $0.terminal!.scrollbackLines = newValue
                                }
                            }
                        ),
                        in: 1000...200_000,
                        step: 5000
                    ) {
                        Text("\(store.config.terminal?.scrollbackLines ?? 50000)")
                            .monospacedDigit()
                    }
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
                .frame(height: 100)
                .scrollContentBackground(.hidden)
                .padding(4)
                .background(Color(nsColor: .controlBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 6))

                HStack {
                    Spacer()
                    Button("Reset to Defaults") {
                        store.update {
                            $0.terminal?.tmuxConfigOverride = nil
                        }
                    }
                    .foregroundStyle(.red)
                }
            }
        }
        .formStyle(.grouped)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func terminalBinding(_ keyPath: WritableKeyPath<ForgeConfig.TerminalSettings, String?>, default defaultValue: String) -> Binding<String> {
        Binding(
            get: { store.config.terminal?[keyPath: keyPath] ?? defaultValue },
            set: { newValue in
                store.update {
                    if $0.terminal == nil { $0.terminal = ForgeConfig.TerminalSettings() }
                    $0.terminal![keyPath: keyPath] = newValue.isEmpty ? nil : newValue
                }
            }
        )
    }

    static let defaultTmuxConfig = """
    set -g status off
    set -g mouse on
    set -g default-terminal "xterm-256color"
    set -g history-limit 50000
    """
}
