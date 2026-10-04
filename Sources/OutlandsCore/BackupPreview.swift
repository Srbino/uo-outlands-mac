import Foundation

public struct BackupPreview: Sendable {
    public let files: Int
    public let bytes: Int64
    public let profileFiles: Int
    public let scripts: Int
    public let macros: Int
    public let externalLinks: Int
    public static func inspect(wrapper: URL, kind: BackupKind) throws -> BackupPreview {
        let roots = kind == .settings ? try SettingsBackup.selected(wrapper).map { wrapper.appendingPathComponent($0) } : [wrapper]
        var files = 0, bytes: Int64 = 0, profiles = 0, scripts = 0, macros = 0, links = 0
        func count(_ url: URL) throws {
            try Task.checkCancellation()
            let info = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
            if info.isSymbolicLink == true { links += 1; return }
            guard info.isRegularFile == true else { return }
            files += 1
            let sum = bytes.addingReportingOverflow(Int64(info.fileSize ?? 0))
            guard !sum.overflow else { throw InstallerError("Backup size exceeds the supported limit.") }
            bytes = sum.partialValue
            let path = url.path.lowercased()
            if path.contains("/profiles/"), ["xml", "json"].contains(url.pathExtension.lowercased()) { profiles += 1 }
            if path.contains("/scripts/") { scripts += 1 }
            if path.contains("/macros/") || url.lastPathComponent.lowercased() == "macros.xml" { macros += 1 }
        }
        for root in roots {
            try count(root)
            if try root.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey]).isDirectory == true,
               try root.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink != true {
                var failure: Error?
                guard let scan = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey], errorHandler: { _, error in failure = error; return false }) else { throw InstallerError("Cannot inspect backup files.") }
                for case let file as URL in scan { try count(file) }
                if let failure { throw failure }
            }
        }
        return BackupPreview(files: files, bytes: bytes, profileFiles: profiles, scripts: scripts, macros: macros, externalLinks: links)
    }
}
