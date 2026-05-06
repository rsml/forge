import SwiftUI
import ForgeCore
import UserNotifications

struct GeneralSettingsPane: View {
    @Environment(NotificationToastState.self) private var toastState
    private var store: ForgeConfigStore { .shared }
    @State private var authorizationDenied = false
    @State private var showFilePicker = false

    private static let systemSounds = [
        "Default", "Basso", "Blow", "Bottle", "Frog", "Funk",
        "Glass", "Hero", "Morse", "Ping", "Pop", "Purr",
        "Sosumi", "Submarine", "Tink",
    ]

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

            Section("Notifications") {
                Toggle("Enable notifications", isOn: notificationsToggle)

                if authorizationDenied {
                    Label {
                        Text("Forge doesn't have permission to send notifications. Open System Settings > Notifications > Forge to allow.")
                    } icon: {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.yellow)
                    }
                    .font(.callout)
                }

                soundPicker

                Button("Send Test Notification") {
                    let sound = store.config.general?.notificationSound
                    let notifier = MacNotificationAdapter(toastState: toastState)
                    Task {
                        _ = await notifier.requestPermission()
                        await notifier.send(
                            title: "Test Notification",
                            body: "Forge notifications are working.",
                            sound: sound
                        )
                        checkAuthorizationStatus()
                    }
                }
            }

        }
        .formStyle(.grouped)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear { checkAuthorizationStatus() }
    }

    private var notificationsToggle: Binding<Bool> {
        Binding(
            get: { store.config.general?.notificationsEnabled ?? false },
            set: { newValue in
                if newValue {
                    Task {
                        let notifier = MacNotificationAdapter(toastState: toastState)
                        _ = await notifier.requestPermission()
                        store.update { config in
                            if config.general == nil { config.general = ForgeConfig.GeneralSettings() }
                            config.general!.notificationsEnabled = true
                        }
                        checkAuthorizationStatus()
                    }
                } else {
                    store.update { config in
                        if config.general == nil { config.general = ForgeConfig.GeneralSettings() }
                        config.general!.notificationsEnabled = false
                    }
                    authorizationDenied = false
                }
            }
        )
    }

    @ViewBuilder
    private var soundPicker: some View {
        let currentSound = store.config.general?.notificationSound ?? "Default"
        let isCustom = !Self.systemSounds.contains(currentSound)

        Picker("Notification sound", selection: Binding(
            get: { isCustom ? "Custom..." : currentSound },
            set: { newValue in
                if newValue == "Custom..." {
                    showFilePicker = true
                } else {
                    store.update { config in
                        if config.general == nil { config.general = ForgeConfig.GeneralSettings() }
                        config.general!.notificationSound = newValue == "Default" ? nil : newValue
                    }
                    previewSound(newValue == "Default" ? nil : newValue)
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
                if config.general == nil { config.general = ForgeConfig.GeneralSettings() }
                config.general!.notificationSound = url.path
            }
            previewSound(url.path)
        }
    }

    private func previewSound(_ sound: String?) {
        MacNotificationAdapter(toastState: toastState).playSound(sound)
    }

    private func checkAuthorizationStatus() {
        guard Bundle.main.bundleIdentifier != nil else { return }
        Task {
            let settings = await UNUserNotificationCenter.current().notificationSettings()
            let enabled = store.config.general?.notificationsEnabled ?? false
            authorizationDenied = enabled && settings.authorizationStatus != .authorized
        }
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
