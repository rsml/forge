import SwiftUI
import ForgeCore

struct FontSettingsPane: View {
    private var store: ForgeConfigStore { .shared }

    private static let monoFonts: [String] = {
        let fm = NSFontManager.shared
        var families: [String] = []
        for family in fm.availableFontFamilies {
            if let members = fm.availableMembers(ofFontFamily: family),
               let first = members.first,
               let traits = first[3] as? UInt,
               (traits & UInt(NSFontTraitMask.fixedPitchFontMask.rawValue)) != 0 {
                families.append(family)
            }
        }
        let known = ["Menlo", "Monaco", "SF Mono", "Courier New", "Dank Mono",
                     "JetBrains Mono", "JetBrainsMono Nerd Font", "Fira Code",
                     "FiraCode Nerd Font", "MesloLGS NF", "MesloLGM Nerd Font",
                     "Hack Nerd Font", "SauceCodePro Nerd Font", "DejaVuSansMono Nerd Font",
                     "Source Code Pro", "IBM Plex Mono"]
        for name in known {
            if !families.contains(name), NSFont(name: name, size: 13) != nil {
                families.append(name)
            }
        }
        return families.sorted()
    }()

    private static let allFonts: [String] = {
        NSFontManager.shared.availableFontFamilies.sorted()
    }()

    var body: some View {
        Form {
            fontSection(
                title: "Primary Font",
                subtitle: "Used for project names and headings",
                config: store.config.primaryFont,
                defaultFamily: ".AppleSystemUIFont",
                defaultSize: 13,
                keyPath: \ForgeConfig.primaryFont,
                fontList: Self.allFonts
            )

            fontSection(
                title: "Secondary Font",
                subtitle: "Used for tab names and captions",
                config: store.config.secondaryFont,
                defaultFamily: ".AppleSystemUIFont",
                defaultSize: 11,
                keyPath: \ForgeConfig.secondaryFont,
                fontList: Self.allFonts
            )

            fontSection(
                title: "Terminal Font",
                subtitle: "Used in terminal emulator — monospace recommended",
                config: store.config.terminalFont,
                defaultFamily: "Menlo",
                defaultSize: 13,
                keyPath: \ForgeConfig.terminalFont,
                fontList: Self.monoFonts
            )
        }
        .formStyle(.grouped)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private func fontSection(
        title: String,
        subtitle: String,
        config: ForgeConfig.FontConfig?,
        defaultFamily: String,
        defaultSize: Int,
        keyPath: WritableKeyPath<ForgeConfig, ForgeConfig.FontConfig?>,
        fontList: [String]
    ) -> some View {
        Section {
            Picker("Family", selection: Binding(
                get: { config?.family ?? defaultFamily },
                set: { v in
                    store.update {
                        if $0[keyPath: keyPath] == nil { $0[keyPath: keyPath] = ForgeConfig.FontConfig() }
                        $0[keyPath: keyPath]!.family = v
                    }
                }
            )) {
                ForEach(fontList, id: \.self) { name in
                    Text(name).tag(name)
                }
            }

            HStack {
                Text("Size")
                Spacer()
                TextField("", value: Binding(
                    get: { config?.size ?? defaultSize },
                    set: { v in
                        store.update {
                            if $0[keyPath: keyPath] == nil { $0[keyPath: keyPath] = ForgeConfig.FontConfig() }
                            $0[keyPath: keyPath]!.size = min(max(v, 8), 36)
                        }
                    }
                ), format: .number)
                .multilineTextAlignment(.trailing)
                .frame(width: 50)

                Stepper("", value: Binding(
                    get: { config?.size ?? defaultSize },
                    set: { v in
                        store.update {
                            if $0[keyPath: keyPath] == nil { $0[keyPath: keyPath] = ForgeConfig.FontConfig() }
                            $0[keyPath: keyPath]!.size = v
                        }
                    }
                ), in: 8...36)
                .labelsHidden()
            }

            // Live preview
            let family = config?.family ?? defaultFamily
            let size = CGFloat(config?.size ?? defaultSize)
            let displayFamily = family == ".AppleSystemUIFont" ? "SF Pro" : family
            Text("The quick brown fox jumps over the lazy dog — \(displayFamily) \(Int(size))pt")
                .font(.custom(family, size: size))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 4)
        } header: {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
