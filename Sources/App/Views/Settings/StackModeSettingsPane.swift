import SwiftUI
import ForgeDomain

struct StackModeSettingsPane: View {
    var body: some View {
        Form {
            Section {
                Text("Stack mode displays sessions as a single vertical stack without a sidebar — focused on one session at a time.")
                    .foregroundStyle(.secondary)
                    .font(.callout)
            }
        }
        .formStyle(.grouped)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
