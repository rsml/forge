import SwiftUI
import ForgeDomain
import AppKit

struct StackModeSettingsPane: View {
    private var store: ForgeConfigStore { .shared }
    @State private var showFilePicker = false

    private static let systemSounds = [
        "Default", "Basso", "Blow", "Bottle", "Frog", "Funk",
        "Glass", "Hero", "Morse", "Ping", "Pop", "Purr",
        "Sosumi", "Submarine", "Tink",
    ]

    var body: some View {
        Form {
            Section {
                Text("Stack mode displays sessions as a single vertical stack without a sidebar — focused on one session at a time.")
                    .foregroundStyle(.secondary)
                    .font(.callout)
            }

            Section("Layout") {
                Picker("Toolbar position", selection: stackBinding(\.toolbarPosition, default: "bottom")) {
                    Text("Top").tag("top")
                    Text("Bottom").tag("bottom")
                }
                .pickerStyle(.segmented)
            }

            Section("Attention") {
                Picker("Bring to foreground", selection: stackBinding(\.bringToForeground, default: "never")) {
                    Text("Never").tag("never")
                    Text("Always").tag("always")
                }

                Picker("Notify", selection: stackBinding(\.notify, default: "never")) {
                    Text("Never").tag("never")
                    Text("Always").tag("always")
                }

                soundPicker
            }

            Section {
                Button("Send Test Notification") {
                    let sound = store.config.stackView?.notificationSound
                    let notifier = MacNotificationAdapter()
                    Task {
                        await notifier.send(
                            title: "Test Notification",
                            body: "Stack mode notifications are working.",
                            sound: sound
                        )
                    }
                }
            }
        }
        .formStyle(.grouped)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private var soundPicker: some View {
        let currentSound = store.config.stackView?.notificationSound ?? "Default"
        let isCustom = !Self.systemSounds.contains(currentSound)

        Picker("Notification sound", selection: Binding(
            get: { isCustom ? "Custom..." : currentSound },
            set: { newValue in
                if newValue == "Custom..." {
                    showFilePicker = true
                } else {
                    store.update { config in
                        if config.stackView == nil { config.stackView = ForgeConfig.StackViewSettings() }
                        config.stackView!.notificationSound = newValue == "Default" ? nil : newValue
                    }
                }
            }
        )) {
            ForEach(Self.systemSounds, id: \.self) { name in
                Text(name).tag(name)
            }
            Divider()
            Text("Custom...").tag("Custom...")
            if isCustom {
                Text(URL(fileURLWithPath: currentSound).lastPathComponent).tag(currentSound)
            }
        }
        .fileImporter(
            isPresented: $showFilePicker,
            allowedContentTypes: [.audio],
            allowsMultipleSelection: false
        ) { result in
            guard case .success(let urls) = result, let url = urls.first else { return }
            store.update { config in
                if config.stackView == nil { config.stackView = ForgeConfig.StackViewSettings() }
                config.stackView!.notificationSound = url.path
            }
        }
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
