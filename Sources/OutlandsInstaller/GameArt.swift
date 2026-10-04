import AppKit
import SwiftUI
import OutlandsCore

/// Game artwork is limited to app identity and sidebar navigation. Actions use native controls.
enum GameGlyph: String, CaseIterable {
    case castle, spyglass, cog
    case chest = "locked-chest"
}

@MainActor
enum GameArt {
    static func resource(_ name: String, extension ext: String) -> URL? {
        Bundle.main.url(forResource: name, withExtension: ext, subdirectory: "GameIcons") ??
            (Bundle.main.bundleURL.pathExtension == "app" ? nil : Bundle.module.url(forResource: name, withExtension: ext, subdirectory: "GameIcons"))
    }
    static let emblem = resource("AppEmblem", extension: "svg").flatMap { NSImage(contentsOf: $0) }
    static let images: [GameGlyph: NSImage] = Dictionary(uniqueKeysWithValues: GameGlyph.allCases.compactMap { glyph in
        guard let url = resource(glyph.rawValue, extension: "svg"), let image = NSImage(contentsOf: url), image.isValid else { return nil }
        image.isTemplate = true
        return (glyph, image)
    })
    static func validate() throws {
        guard emblem?.isValid == true, images.count == GameGlyph.allCases.count, resource("CREDITS", extension: "txt") != nil else {
            throw InstallerError("The app is missing game artwork or its credits. Download a complete build.")
        }
    }
}

struct GameIcon: View {
    let glyph: GameGlyph
    var size: CGFloat = 22
    var body: some View {
        Group {
            if let image = GameArt.images[glyph] {
                Image(nsImage: image).resizable().renderingMode(.template).scaledToFit()
            } else {
                // Packaging self-check rejects this state. Keep layout stable if a running app is damaged.
                Rectangle().strokeBorder(.secondary)
            }
        }.frame(width: size, height: size).accessibilityHidden(true)
    }
}

struct GameLabel: View {
    let title: String
    let glyph: GameGlyph
    var body: some View { HStack(spacing: 9) { GameIcon(glyph: glyph, size: 20); Text(title) } }
}
