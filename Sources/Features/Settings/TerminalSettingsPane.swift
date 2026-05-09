import SwiftUI
import ForgeCore

struct TerminalSettingsPane: View {
    private var store: ForgeConfigStore { .shared }

    private var scrollbackLines: Int { store.config.terminal?.scrollbackLines ?? 50000 }

    @State private var scrollbackText = ""

    var body: some View {
        Form {
            Section("Terminal") {
                LabeledContent("Scrollback lines") {
                    HStack {
                        Spacer()
                        TextField("", text: $scrollbackText)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 80)
                            .onSubmit { commitScrollback() }
                            .onChange(of: scrollbackText) { _, newValue in
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
                }
                .padding(.vertical, -4)

                Toggle("Use tmux for project persistence", isOn: Binding(
                    get: { store.config.terminal?.useTmuxPersistence ?? true },
                    set: { newValue in
                        store.update {
                            if $0.terminal == nil { $0.terminal = ForgeConfig.TerminalSettings() }
                            $0.terminal!.useTmuxPersistence = newValue
                        }
                    }
                ))
                .padding(.vertical, -4)
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
