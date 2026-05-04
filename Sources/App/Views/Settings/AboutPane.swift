import SwiftUI

struct AboutPane: View {
    private var version: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev"
    }
    private var build: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "0"
    }

    var body: some View {
        VStack(spacing: 20) {
            Spacer()

            Image(systemName: "terminal.fill")
                .font(.system(size: 56))
                .foregroundStyle(Color.accentColor)

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
