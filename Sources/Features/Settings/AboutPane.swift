import SwiftUI
import ForgeCore

struct AboutPane: View {
    private var version: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.1"
    }
    private var build: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
    }

    var body: some View {
        VStack(spacing: 20) {
            Spacer()

            Group {
                if let iconPath = bundleResource("appicon-transparent.png"),
                   let nsImage = NSImage(contentsOf: iconPath) {
                    Image(nsImage: nsImage)
                        .resizable()
                        .frame(width: 192, height: 192)
                } else {
                    Image(systemName: "terminal.fill")
                        .font(.system(size: 56))
                        .foregroundStyle(Color.accentColor)
                }
            }

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

            Button {
                NSWorkspace.shared.open(URL(string: "https://github.com/rsml/forge")!)
            } label: {
                Text("View on GitHub")
            }
            .buttonStyle(.bordered)
            .controlSize(.large)

            Button {
                NSWorkspace.shared.open(URL(string: "https://github.com/rsml/forge/blob/main/docs/THEMES.md")!)
            } label: {
                Text("Theme Acknowledgments")
            }
            .buttonStyle(.link)
            .foregroundStyle(.secondary)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
}
