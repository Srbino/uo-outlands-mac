import Foundation

public struct BackupRecord: Codable, Identifiable {
    public var id: String { url.path }
    public let url: URL
    public let created: Date
    public let bytes: Int64
    public var verified: Date?
    public var kind: BackupKind?
    public var scope: BackupKind { kind ?? .full }
    public var name: String?
    public var note: String
    public init(url: URL, created: Date, bytes: Int64, verified: Date?, note: String, kind: BackupKind? = nil) {
        self.url = url; self.created = created; self.bytes = bytes; self.verified = verified; self.note = note; self.kind = kind
    }
}

public enum GameFolder: String, CaseIterable, Identifiable {
    case contents, game, razor, scripts, profiles, backups
    public var id: String { rawValue }
    public func url(paths: Paths) -> URL {
        let game = Paths.launcher(paths.wrapper).deletingLastPathComponent()
        let assistant = game.appendingPathComponent("ClassicUO/Data/Plugins/Assistant")
        let legacy = game.appendingPathComponent("ClassicUO/Data/Plugins/Razor")
        let razor = FileManager.default.fileExists(atPath: assistant.path) ? assistant : legacy
        switch self {
        case .contents: return paths.wrapper.appendingPathComponent("Contents")
        case .game: return game
        case .razor: return razor
        case .scripts: return razor.appendingPathComponent("Scripts")
        case .profiles: return razor.appendingPathComponent("Profiles")
        case .backups: return paths.wrapper.deletingLastPathComponent()
        }
    }
}

extension Snapshot {
    public static func externalLinks(_ root: URL) throws -> [String] {
        let fm = FileManager.default
        guard let items = fm.enumerator(at: root, includingPropertiesForKeys: [.isSymbolicLinkKey]) else { return [] }
        let base = root.resolvingSymlinksInPath().path + "/"
        var result: [String] = []
        for case let url as URL in items {
            try Task.checkCancellation()
            guard (try url.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) == true else { continue }
            let relative = String(url.path.dropFirst(root.path.count + 1))
            // Wine's Z: and system device links are normal; expose game/user links instead.
            guard relative.contains("/drive_c/users/") || relative.contains("/Ultima Online Outlands/") else { continue }
            if !url.resolvingSymlinksInPath().path.hasPrefix(base) { result.append(relative) }
        }
        return result.sorted()
    }
}
