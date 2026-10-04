import Foundation
import OutlandsCore

/// Invoked only by tools/resource_guard.py, never run directly for large inputs.
@main struct BackupMemoryProbe {
    static func compare(source: URL, restored: URL) throws -> (Int, Int) {
        let fm = FileManager.default
        let before = try Snapshot.fingerprint(source)
        let entries = fm.enumerator(at: source, includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey])!
        var files = 0, links = 0
        while let file = entries.nextObject() as? URL {
            try autoreleasepool {
                let relative = String(file.path.dropFirst(source.path.count + 1))
                let target = restored.appendingPathComponent(relative)
                let info = try file.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
                if info.isSymbolicLink == true {
                    guard try fm.destinationOfSymbolicLink(atPath: file.path) == fm.destinationOfSymbolicLink(atPath: target.path) else {
                        throw InstallerError("Restored link mismatch")
                    }
                    links += 1
                } else if info.isRegularFile == true {
                    guard try Integrity.sha256(file) == Integrity.sha256(target) else {
                        throw InstallerError("Restored file mismatch")
                    }
                    files += 1
                }
            }
        }
        guard try Snapshot.fingerprint(source) == before else { throw InstallerError("Source changed") }
        return (files, links)
    }

    static func main() async throws {
        let args = CommandLine.arguments
        guard args.count >= 4, args.dropFirst(2).allSatisfy({ URL(fileURLWithPath: $0).resolvingSymlinksInPath().path.contains("/.qa/") }) else {
            throw InstallerError("Only explicit disposable .qa paths are permitted")
        }
        let mode = args[1], source = URL(fileURLWithPath: args[2]), destination = URL(fileURLWithPath: args[3])
        if mode == "hash" {
            let expected = try Integrity.sha256(source)
            for _ in 0..<128 {
                guard try Integrity.sha256(source) == expected else { throw InstallerError("Hash changed") }
            }
            print("128 repeated checksums passed")
        } else if mode == "verify" {
            let engine = Backups(log: try SessionLog(directory: destination))
            let manifest = try await engine.verify(source)
            print("Archive verified: \(manifest.bytes) compressed bytes")
        } else if mode == "restore" {
            let engine = Backups(log: try SessionLog(directory: destination.appendingPathComponent("logs")))
            let result = try await engine.restoreResult(source, into: destination)
            print("Separate restore completed: \(result.folder.lastPathComponent); scope \(result.kind.rawValue)")
        } else if mode == "compare" {
            let result = try compare(source: source, restored: destination)
            print("Compared \(result.0) files and \(result.1) links; source unchanged")
        } else {
            throw InstallerError("Unsupported QA mode")
        }
    }
}
