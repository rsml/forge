import SwiftUI

struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralSettingsPane()
                .tabItem { Label("General", systemImage: "gearshape") }
            ThemeSettingsPane()
                .tabItem { Label("Theme", systemImage: "paintbrush.fill") }
            TerminalSettingsPane()
                .tabItem { Label("Terminal", systemImage: "terminal") }
            ShortcutsSettingsPane()
                .tabItem { Label("Shortcuts", systemImage: "keyboard") }
            AboutPane()
                .tabItem { Label("About", systemImage: "info.circle") }
        }
        .frame(width: 700, height: 550)
    }
}
