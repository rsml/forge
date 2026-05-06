import SwiftUI

struct ThemeDefinition: Identifiable {
    let id: String
    let name: String
    let background: Color
    let foreground: Color
    let cursor: Color?
    let ansiColors: [Color]  // 0-15

    var previewColors: [Color] {
        let samples = [foreground, background]
            + ansiColors.prefix(8).map { $0 }
        return Array(samples.prefix(10))
    }
}
