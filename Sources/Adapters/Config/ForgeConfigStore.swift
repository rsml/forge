import SwiftUI

@Observable @MainActor
final class ForgeConfigStore {
    static let shared = ForgeConfigStore()
    private(set) var config: ForgeConfig

    private init() { config = ForgeConfig.load() }

    func update(_ mutate: (inout ForgeConfig) -> Void) {
        mutate(&config)
        config.save()
    }
}
