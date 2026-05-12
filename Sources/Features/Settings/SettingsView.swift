import SwiftUI
import ForgeCore

struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralSettingsPane()
                .tabItem { Label("General", systemImage: "gearshape") }
            NotificationsSettingsPane()
                .tabItem { Label("Notifications", systemImage: "bell.fill") }
            ListModeSettingsPane()
                .tabItem { Label("List Mode", systemImage: "list.bullet") }
            StackModeSettingsPane()
                .tabItem { Label("Stack Mode", systemImage: "rectangle.stack") }
            ThemeSettingsPane()
                .tabItem { Label("Theme", systemImage: "paintbrush.fill") }
            FontSettingsPane()
                .tabItem { Label("Fonts", systemImage: "textformat") }
            TerminalSettingsPane()
                .tabItem { Label("Terminal", systemImage: "terminal") }
            ShortcutsSettingsPane()
                .tabItem { Label("Shortcuts", systemImage: "keyboard") }
            AboutPane()
                .tabItem { Label("About", systemImage: "info.circle") }
        }
        .frame(width: 850, height: 550)
    }
}
