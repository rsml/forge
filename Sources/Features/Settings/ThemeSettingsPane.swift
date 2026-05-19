import SwiftUI
import ForgeCore

struct ThemeSettingsPane: View {
    private var store: ForgeConfigStore { .shared }
    @State private var themes: [ThemeDefinition] = []
    @State private var searchText = ""

    private var filteredThemes: [ThemeDefinition] {
        if searchText.isEmpty { return themes }
        let term = searchText.lowercased()
        return themes.filter { $0.name.lowercased().contains(term) || $0.id.lowercased().contains(term) }
    }

    private let columns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12),
    ]

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Filter themes...", text: $searchText)
                    .textFieldStyle(.plain)
            }
            .padding(10)
            .background(Color(nsColor: .textBackgroundColor).opacity(0.5))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .padding(.horizontal, 16)
            .padding(.top, 12)

            ScrollView {
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(filteredThemes) { theme in
                        ThemePreviewCard(
                            theme: theme,
                            isSelected: store.config.theme?.source == theme.id,
                            onSelect: {
                                store.update { $0.theme = ForgeConfig.ThemeConfig(source: theme.id) }
                            }
                        )
                    }
                }
                .padding(16)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onDisappear {
            NotificationCenter.default.post(name: .forgeThemeHoverEnded, object: nil)
        }
        .onAppear {
            if themes.isEmpty {
                Task.detached {
                    let loaded = ThemeParser.loadAllThemes()
                    await MainActor.run { themes = loaded }
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .forgeThemesChanged)) { _ in
            Task.detached {
                let loaded = ThemeParser.loadAllThemes()
                await MainActor.run { themes = loaded }
            }
        }
    }
}
