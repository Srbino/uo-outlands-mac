import Foundation

public enum BackupKind: String, Codable, Sendable {
    case full, settings
    public var title: String { self == .settings ? "Settings & scripts" : "Full installation" }
}

/// Deliberately excludes the Wine engine, game assets, plugin binaries and journal logs.
/// The original wrapper-relative layout makes recovered settings easy to compare/copy.
enum SettingsBackup {
    static let base = "Contents/SharedSupport/prefix/drive_c" + AppInfo.program.replacingOccurrences(of: "/Outlands.exe", with: "") + "/ClassicUO"
    static let directories = ["Data/Profiles", "Data/Client/MapIcons", "Data/Client/Fonts"] +
        ["Assistant", "Razor"].flatMap { plugin in
            ["Profiles", "Scripts", "Macros", "Language"].map { "Data/Plugins/\(plugin)/\($0)" }
        }
    static let extensions: Set<String> = ["xml", "json", "csv", "def", "ini", "cfg", "config", "txt", "usr", "bak"]
    static let fileFolders = ["Data/Client", "Data/Plugins/Assistant", "Data/Plugins/Razor"]

    static func selected(_ wrapper: URL) throws -> [String] {
        let fm = FileManager.default
        var result: [String] = []
        func add(_ relative: String) throws {
            let url = wrapper.appendingPathComponent(relative)
            guard fm.fileExists(atPath: url.path) || (try? url.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) == true else { return }
            guard url.resolvingSymlinksInPath() == url.standardizedFileURL else {
                throw InstallerError("A settings location is redirected by a symbolic link. Back up its external target separately or use a full backup.")
            }
            result.append(relative)
        }
        try add(base + "/settings.json")
        for directory in directories { try add(base + "/" + directory) }
        for folder in fileFolders {
            let url = wrapper.appendingPathComponent(base + "/" + folder)
            guard fm.fileExists(atPath: url.path) else { continue }
            guard url.resolvingSymlinksInPath() == url.standardizedFileURL else {
                throw InstallerError("A settings folder is redirected. Back up its external target separately.")
            }
            for file in try fm.contentsOfDirectory(at: url, includingPropertiesForKeys: [.isRegularFileKey]) {
                if extensions.contains(file.pathExtension.lowercased()), try file.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true {
                    try add(base + "/" + folder + "/" + file.lastPathComponent)
                }
            }
        }
        guard !result.isEmpty else { throw InstallerError("No ClassicUO or Razor settings were found. Start the game once or choose a full installation backup.") }
        let config = wrapper.appendingPathComponent(base + "/settings.json")
        if result.contains(base + "/settings.json") {
            let handle = try FileHandle(forReadingFrom: config)
            defer { try? handle.close() }
            guard let data = try handle.read(upToCount: 1024 * 1024), data.count < 1024 * 1024,
                  let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                throw InstallerError("ClassicUO settings.json could not be inspected. Choose a full backup until the configuration is readable.")
            }
            if let custom = json["profilespath"] as? String, !custom.isEmpty,
               custom.replacingOccurrences(of: "\\", with: "/").trimmingCharacters(in: CharacterSet(charactersIn: "/")).lowercased() != "data/profiles" {
                throw InstallerError("ClassicUO uses a custom profile path. Back up that location separately; settings backups support the standard Data/Profiles layout.")
            }
        }
        return result.sorted()
    }
    static func fingerprint(_ wrapper: URL) throws -> String {
        try selected(wrapper).map { relative in
            let url = wrapper.appendingPathComponent(relative)
            if try url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory == true {
                return relative + ":" + (try Snapshot.fingerprint(url))
            }
            return relative + ":" + (try Integrity.sha256(url))
        }.joined(separator: "\n")
    }
    static func permits(_ canonicalPath: String, directory: Bool) -> Bool {
        let base = ("outlands.app/" + base).lowercased()
        if canonicalPath == base + "/settings.json" { return !directory }
        let roots = directories.map { base + "/" + $0.lowercased() }
        if roots.contains(where: { canonicalPath == $0 || canonicalPath.hasPrefix($0 + "/") }) { return true }
        for folder in fileFolders {
            let parent = base + "/" + folder.lowercased() + "/"
            if canonicalPath.hasPrefix(parent) {
                let name = String(canonicalPath.dropFirst(parent.count))
                if !directory, !name.contains("/"), extensions.contains((name as NSString).pathExtension) { return true }
            }
        }
        // Tar may include parent directories, but no payloads at those locations.
        let leaves = roots + [base + "/settings.json"] + fileFolders.map { base + "/" + $0.lowercased() + "/placeholder.xml" }
        return directory && leaves.contains { $0.hasPrefix(canonicalPath + "/") }
    }
}
