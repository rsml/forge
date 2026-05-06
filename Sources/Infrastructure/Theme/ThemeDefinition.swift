import Foundation

struct ThemeColor: Sendable {
    let red: Double
    let green: Double
    let blue: Double
}

struct ThemeDefinition: Identifiable {
    let id: String
    let name: String
    let background: ThemeColor
    let foreground: ThemeColor
    let cursor: ThemeColor?
    let ansiColors: [ThemeColor]  // 0-15

    var previewColors: [ThemeColor] {
        let samples = [foreground, background]
            + ansiColors.prefix(8).map { $0 }
        return Array(samples.prefix(10))
    }
}
