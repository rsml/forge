import SwiftUI
import ForgeCore
import UserNotifications

struct NotificationsSettingsPane: View {
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
            Section("Alerts") {
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
                    let sound = store.config.notifications?.sound
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

            Section("Badge") {
                Picker("Badge color", selection: badgeColorModeBinding) {
                    Text("macOS Accent Color").tag("accent")
                    Text("Theme Accent Color").tag("theme")
                    Text("Custom").tag("custom")
                }

                if (store.config.notifications?.badgeColorMode ?? "accent") == "custom" {
                    ColorPicker("Custom color", selection: customColorBinding, supportsOpacity: true)
                        .alignmentGuide(.firstTextBaseline) { d in d[VerticalAlignment.center] }
                }

                LabeledContent("Badge size") {
                    Stepper(
                        value: badgeSizeBinding,
                        in: 4...16,
                        step: 1
                    ) {
                        Text("\(Int(store.config.notifications?.badgeSize ?? 8)) pt")
                            .monospacedDigit()
                            .frame(width: 40)
                    }
                    AttentionDot(needsAttention: true)
                        .padding(.leading, 8)
                }
            }
        }
        .formStyle(.grouped)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear { checkAuthorizationStatus() }
    }

    // MARK: - Notifications Toggle

    private var notificationsToggle: Binding<Bool> {
        Binding(
            get: { store.config.notifications?.enabled ?? false },
            set: { newValue in
                if newValue {
                    Task {
                        let notifier = MacNotificationAdapter(toastState: toastState)
                        _ = await notifier.requestPermission()
                        store.update { config in
                            if config.notifications == nil { config.notifications = ForgeConfig.NotificationSettings() }
                            config.notifications!.enabled = true
                        }
                        checkAuthorizationStatus()
                    }
                } else {
                    store.update { config in
                        if config.notifications == nil { config.notifications = ForgeConfig.NotificationSettings() }
                        config.notifications!.enabled = false
                    }
                    authorizationDenied = false
                }
            }
        )
    }

    // MARK: - Sound Picker

    @ViewBuilder
    private var soundPicker: some View {
        let currentSound = store.config.notifications?.sound ?? "Default"
        let isCustom = !Self.systemSounds.contains(currentSound)

        Picker("Notification sound", selection: Binding(
            get: { isCustom ? "Custom..." : currentSound },
            set: { newValue in
                if newValue == "Custom..." {
                    showFilePicker = true
                } else {
                    store.update { config in
                        if config.notifications == nil { config.notifications = ForgeConfig.NotificationSettings() }
                        config.notifications!.sound = newValue == "Default" ? nil : newValue
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
                if config.notifications == nil { config.notifications = ForgeConfig.NotificationSettings() }
                config.notifications!.sound = url.path
            }
            previewSound(url.path)
        }
    }

    // MARK: - Badge Appearance Bindings

    private var badgeColorModeBinding: Binding<String> {
        Binding(
            get: { store.config.notifications?.badgeColorMode ?? "accent" },
            set: { newValue in
                store.update { config in
                    if config.notifications == nil { config.notifications = ForgeConfig.NotificationSettings() }
                    config.notifications!.badgeColorMode = newValue
                }
            }
        )
    }

    private var customColorBinding: Binding<Color> {
        Binding(
            get: {
                if let hex = store.config.notifications?.badgeCustomColor {
                    return Color(hex: hex)
                }
                return Color.accentColor
            },
            set: { newColor in
                let hex = newColor.hexString
                store.update { config in
                    if config.notifications == nil { config.notifications = ForgeConfig.NotificationSettings() }
                    config.notifications!.badgeCustomColor = hex
                }
            }
        )
    }

    private var badgeSizeBinding: Binding<Double> {
        Binding(
            get: { store.config.notifications?.badgeSize ?? 8 },
            set: { newValue in
                store.update { config in
                    if config.notifications == nil { config.notifications = ForgeConfig.NotificationSettings() }
                    config.notifications!.badgeSize = newValue
                }
            }
        )
    }

    // MARK: - Helpers

    private func previewSound(_ sound: String?) {
        MacNotificationAdapter(toastState: toastState).playSound(sound)
    }

    private func checkAuthorizationStatus() {
        guard Bundle.main.bundleIdentifier != nil else { return }
        Task {
            let settings = await UNUserNotificationCenter.current().notificationSettings()
            let enabled = store.config.notifications?.enabled ?? false
            authorizationDenied = enabled && settings.authorizationStatus != .authorized
        }
    }
}

