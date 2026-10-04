import Foundation
import Darwin
import CryptoKit

/// Open the package directory and its regular files without following replacement symlinks.
/// Restoration copies these pinned bytes into private staging before validation/extraction.
final class BackupInput {
    let manifest: BackupManifest
    let payload: FileHandle
    init(_ backup: URL) throws {
        let directory = Darwin.open(backup.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard directory >= 0 else { throw InstallerError("Cannot open the backup package, or it is a symbolic link.") }
        defer { Darwin.close(directory) }
        let manifestFile = try Self.regular(directory: directory, name: "manifest.json")
        defer { try? manifestFile.close() }
        guard let data = try manifestFile.read(upToCount: 65_536), data.count < 65_536 else {
            throw InstallerError("Invalid backup manifest.")
        }
        manifest = try JSONDecoder().decode(BackupManifest.self, from: data)
        guard ((manifest.format == 1 && manifest.scope == .full) || (manifest.format == 2 && manifest.kind == .settings)), manifest.bytes > 0, manifest.expandedBytes >= 0,
              manifest.expandedBytes < Int64.max - 512 * 1024 * 1024,
              manifest.sha256.range(of: "^[a-f0-9]{64}$", options: .regularExpression) != nil else {
            throw InstallerError("Invalid backup manifest.")
        }
        payload = try Self.regular(directory: directory, name: "outlands.tar.gz")
        guard try stamp().size == manifest.bytes else {
            try? payload.close()
            throw InstallerError("Backup integrity check failed: payload size does not match.")
        }
    }
    deinit { try? payload.close() }
    struct Stamp: Equatable {
        let size: Int64
        let modifiedSeconds: Int
        let modifiedNanoseconds: Int
        let changedSeconds: Int
        let changedNanoseconds: Int
    }
    func stamp() throws -> Stamp {
        var info = stat()
        guard fstat(payload.fileDescriptor, &info) == 0 else { throw InstallerError("The backup disk is unavailable.") }
        return Stamp(size: info.st_size, modifiedSeconds: info.st_mtimespec.tv_sec, modifiedNanoseconds: info.st_mtimespec.tv_nsec,
                     changedSeconds: info.st_ctimespec.tv_sec, changedNanoseconds: info.st_ctimespec.tv_nsec)
    }
    @discardableResult func verify() throws -> Int64 {
        let initial = try stamp()
        try copyChecked(to: nil)
        let expanded = try BackupArchive.inspect(fd: payload.fileDescriptor, expandedLimit: manifest.expandedBytes, kind: manifest.scope)
        guard try stamp() == initial else { throw InstallerError("The backup changed while being verified. Retry with a stable copy.") }
        return expanded
    }
    func copyChecked(to destination: URL?) throws {
        try payload.seek(toOffset: 0)
        var output: FileHandle?
        if let destination {
            let fd = Darwin.open(destination.path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0o600)
            guard fd >= 0 else { throw InstallerError("Cannot create the private backup copy.") }
            output = FileHandle(fileDescriptor: fd, closeOnDealloc: true)
        }
        defer { try? output?.close() }
        var hash = SHA256()
        var bytes: Int64 = 0
        while true {
            try Task.checkCancellation()
            let count = try autoreleasepool {
                let chunk = try payload.read(upToCount: 1024 * 1024) ?? Data()
                bytes += Int64(chunk.count)
                guard bytes <= manifest.bytes else { throw InstallerError("The backup payload grew during verification.") }
                hash.update(data: chunk)
                try output?.write(contentsOf: chunk)
                return chunk.count
            }
            if count == 0 { break }
        }
        let digest = hash.finalize().map { String(format: "%02x", $0) }.joined()
        guard bytes == manifest.bytes, digest == manifest.sha256 else {
            throw InstallerError("Backup integrity check failed. The package is incomplete or damaged; nothing was restored.")
        }
    }
    private static func regular(directory: Int32, name: String) throws -> FileHandle {
        let fd = openat(directory, name, O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC)
        var info = stat()
        guard fd >= 0 else { throw InstallerError("A backup file is missing, inaccessible or redirected.") }
        guard fstat(fd, &info) == 0, info.st_mode & S_IFMT == S_IFREG else {
            Darwin.close(fd)
            throw InstallerError("Backup manifests and payloads must be regular files, not links, devices or pipes.")
        }
        return FileHandle(fileDescriptor: fd, closeOnDealloc: true)
    }
}
