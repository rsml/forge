import SwiftUI

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
                if let iconPath = Bundle.main.executableURL?.deletingLastPathComponent()
                    .appendingPathComponent("appicon-transparent.png"),
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

            Link("View on GitHub", destination: URL(string: "https://github.com/anthropics/forge")!)
                .font(.callout)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
}
