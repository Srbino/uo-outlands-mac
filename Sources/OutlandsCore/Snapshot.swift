import Foundation
import CryptoKit
import Darwin

/// Metadata snapshot: detects changes while a closed game is copied/archived.
/// No file contents or profile names are logged; symbolic links are never followed.
public enum Snapshot {
    public static func fingerprint(_ root: URL) throws -> String {
        let fm = FileManager.default
        let keys: [URLResourceKey] = [.isSymbolicLinkKey, .fileSizeKey, .contentModificationDateKey, .fileResourceIdentifierKey]
        var failure: Error?
        guard let entries = fm.enumerator(at: root, includingPropertiesForKeys: keys, errorHandler: { _, error in failure = error; return false }) else {
            throw InstallerError("Cannot inspect installation files.")
        }
        var records: [String] = []
        for case let url as URL in entries {
            try Task.checkCancellation()
            let info = try url.resourceValues(forKeys: Set(keys))
            let relative = String(url.path.dropFirst(root.path.count))
            let link = info.isSymbolicLink == true ? try fm.destinationOfSymbolicLink(atPath: url.path) : ""
            var metadata = stat()
            guard lstat(url.path, &metadata) == 0 else { throw InstallerError("Installation files changed or became inaccessible during inspection.") }
            let changed = "\(metadata.st_ctimespec.tv_sec):\(metadata.st_ctimespec.tv_nsec):\(metadata.st_mode)"
            records.append("\(relative.utf8.count):\(relative)|\(info.fileSize ?? 0)|\(info.contentModificationDate?.timeIntervalSince1970 ?? 0)|\(String(describing: info.fileResourceIdentifier))|\(link)|\(changed)")
        }
        if let failure { throw failure }
        var hash = SHA256()
        for record in records.sorted() { hash.update(data: Data((record + "\n").utf8)) }
        return hash.finalize().map { String(format: "%02x", $0) }.joined()
    }
}
