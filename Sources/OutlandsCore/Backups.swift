import Foundation

public struct BackupManifest: Codable, Sendable {
    public let format: Int
    public let created: Date
    public let installer: String
    public let sha256: String
    public let bytes: Int64
    public let expandedBytes: Int64
    public let kind: BackupKind?
    public var scope: BackupKind { kind ?? .full }
    public init(format: Int, created: Date, installer: String, sha256: String, bytes: Int64, expandedBytes: Int64, kind: BackupKind? = nil) {
        self.format = format; self.created = created; self.installer = installer; self.sha256 = sha256
        self.bytes = bytes; self.expandedBytes = expandedBytes; self.kind = kind
    }
}

/// Local, portable backup packages. Never follows Wine's links into the user's home.
public struct BackupRestoration: Sendable {
    public let folder: URL
    public let kind: BackupKind
}

public actor Backups {
    private let log: SessionLog
    private let fm = FileManager.default
    public init(log: SessionLog) { self.log = log }

    @discardableResult public func create(wrapper: URL, destination: URL, lockDirectory: URL, kind: BackupKind = .full, progress: @MainActor @Sendable (String) -> Void = { _ in }) async throws -> BackupManifest {
        let lock = try InstallLock(directory: lockDirectory)
        defer { withExtendedLifetime(lock) {} }
        let source = wrapper.resolvingSymlinksInPath()
        guard wrapper.lastPathComponent == "outlands.app", source == wrapper.standardizedFileURL,
              fm.fileExists(atPath: wrapper.appendingPathComponent("Contents/Info.plist").path) else {
            throw InstallerError("Select a real outlands.app installation, not a symbolic link.")
        }
        let target = destination.resolvingSymlinksInPath()
        guard !target.path.hasPrefix(source.path + "/"), !fm.fileExists(atPath: target.path) else {
            throw InstallerError("Choose a new backup name outside the game application. Existing backups are never overwritten.")
        }
        try kind == .settings ? GameProcesses.requireSettingsClosed(wrapper) : GameProcesses.requireClosed(wrapper)
        await progress("Inspecting game files…")
        let selection = kind == .settings ? try SettingsBackup.selected(wrapper) : []
        let snapshot = kind == .settings ? try SettingsBackup.fingerprint(wrapper) : try Snapshot.fingerprint(wrapper)
        let size = kind == .settings ? try selection.reduce(Int64(0)) { total, path in
            let next = try treeBytes(wrapper.appendingPathComponent(path))
            let sum = total.addingReportingOverflow(next)
            guard !sum.overflow, sum.partialValue < Int64.max - 512 * 1024 * 1024 else { throw InstallerError("Settings are too large to archive.") }
            return sum.partialValue
        } : try treeBytes(wrapper)
        try requireSpace(at: target.deletingLastPathComponent(), bytes: size + 512 * 1024 * 1024)
        let staging = target.deletingLastPathComponent().appendingPathComponent(".outlands-backup-\(UUID().uuidString)")
        try fm.createDirectory(at: staging, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        defer { try? fm.removeItem(at: staging) }
        let payload = staging.appendingPathComponent("outlands.tar.gz")
        log.write(kind == .settings ? "Archiving ClassicUO and Razor settings, profiles, scripts and macros. Game assets and runtime binaries are excluded." : "Archiving the whole wrapper. External symlink targets are not copied.")
        await progress(kind == .settings ? "Compressing settings and scripts…" : "Compressing the entire Outlands application…")
        let members = kind == .settings ? selection.map { "outlands.app/" + $0 } : ["outlands.app"]
        _ = try await Command.run("/usr/bin/tar", ["-czf", payload.path, "-C", wrapper.deletingLastPathComponent().path] + members, timeout: 14400, log: log)
        try kind == .settings ? GameProcesses.requireSettingsClosed(wrapper) : GameProcesses.requireClosed(wrapper)
        let after = kind == .settings ? try SettingsBackup.fingerprint(wrapper) : try Snapshot.fingerprint(wrapper)
        guard after == snapshot else {
            throw InstallerError("Game files changed during backup. Close the game and retry. No inconsistent archive was saved.")
        }
        try Task.checkCancellation()
        let bytes = Int64(try payload.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0)
        let manifest = BackupManifest(format: kind == .settings ? 2 : 1, created: Date(), installer: AppInfo.version,
                                      sha256: try Integrity.sha256(payload), bytes: bytes, expandedBytes: size, kind: kind)
        try JSONEncoder().encode(manifest).write(to: staging.appendingPathComponent("manifest.json"), options: .atomic)
        _ = try await verify(staging, progress: progress)
        try Task.checkCancellation()
        try fm.moveItem(at: staging, to: target)
        log.write("Backup completed and verified: \(target.path)")
        return manifest
    }

    @discardableResult public func verify(_ backup: URL, progress: @MainActor @Sendable (String) -> Void = { _ in }) async throws -> BackupManifest {
        await progress("Verifying backup checksum…")
        let input = try BackupInput(backup)
        try input.verify()
        try Task.checkCancellation()
        return input.manifest
    }

    /// Restore alongside an existing installation, never replace or automatically launch it.
    public func restore(_ backup: URL, into parent: URL, progress: @MainActor @Sendable (String) -> Void = { _ in }) async throws -> URL {
        try await restoreResult(backup, into: parent, progress: progress).folder
    }
    public func restoreResult(_ backup: URL, into parent: URL, progress: @MainActor @Sendable (String) -> Void = { _ in }) async throws -> BackupRestoration {
        let input = try BackupInput(backup)
        let manifest = input.manifest
        let destination = parent.appendingPathComponent("Outlands-restored-\(UUID().uuidString)")
        let (required, overflow) = manifest.expandedBytes.addingReportingOverflow(manifest.bytes)
        guard !overflow, required < Int64.max - 512 * 1024 * 1024 else { throw InstallerError("Invalid backup size.") }
        try requireSpace(at: parent, bytes: required + 512 * 1024 * 1024)
        let staging = parent.appendingPathComponent(".outlands-restore-\(UUID().uuidString)")
        try fm.createDirectory(at: staging, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        defer { try? fm.removeItem(at: staging) }
        await progress("Copying and verifying backup in private staging…")
        let payload = staging.appendingPathComponent("payload.tar.gz")
        try input.copyChecked(to: payload)
        let privateFile = try FileHandle(forReadingFrom: payload)
        defer { try? privateFile.close() }
        _ = try BackupArchive.inspect(fd: privateFile.fileDescriptor, expandedLimit: manifest.expandedBytes, kind: manifest.scope)
        try Task.checkCancellation()
        await progress("Restoring into a separate folder…")
        _ = try await Command.run("/usr/bin/tar", ["-xzf", payload.path,
                                                   "-C", staging.path, "--no-same-owner"], timeout: 14400, log: log, logOutput: false)
        try Task.checkCancellation()
        if manifest.scope == .full {
            for suffix in ["outlands.app", "outlands.app/Contents", "outlands.app/Contents/Info.plist"] {
                guard (try staging.appendingPathComponent(suffix).resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) != true else {
                    throw InstallerError("The restored application structure contains an unsafe symbolic link.")
                }
            }
            guard fm.fileExists(atPath: staging.appendingPathComponent("outlands.app/Contents/Info.plist").path) else {
                throw InstallerError("The restored archive does not contain an application bundle.")
            }
        } else {
            let instructions = """
            Recovered Outlands settings and scripts

            This is a settings backup, not a runnable game installation.
            Close Outlands and Razor before copying any recovered files.
            Keep a backup of your current settings first.
            The files under outlands.app use the same relative paths as the game application.
            In Finder, use Show Package Contents on your installed outlands.app, then copy the recovered settings to the matching locations.
            Profiles, macros and scripts may contain account information. Do not upload this folder.
            External symbolic-link targets are not included. Restore those separately.

            """
            try instructions.write(to: staging.appendingPathComponent("RESTORE-INSTRUCTIONS.txt"), atomically: true, encoding: .utf8)
        }
        try fm.removeItem(at: payload)
        try fm.moveItem(at: staging, to: destination)
        log.write("Backup restored separately: \(destination.path). Your current game was not replaced.")
        return BackupRestoration(folder: destination, kind: manifest.scope)
    }
    public func activate(restored: URL, paths: Paths) async throws -> URL? {
        let lock = try InstallLock(directory: paths.support)
        defer { withExtendedLifetime(lock) {} }
        let source = restored.appendingPathComponent("outlands.app")
        guard source.resolvingSymlinksInPath() == source.standardizedFileURL,
              Wrapper.activationChecks(source).allSatisfy(\.passed),
              source != paths.wrapper else { throw InstallerError("The recovered application is incomplete or redirected. It cannot be activated.") }
        try GameProcesses.requireClosed(source)
        try GameProcesses.requireClosed(paths.wrapper)
        let snapshot = try Snapshot.fingerprint(source)
        try fm.createDirectory(at: paths.wrapper.deletingLastPathComponent(), withIntermediateDirectories: true)
        try requireSpace(at: paths.wrapper.deletingLastPathComponent(), bytes: treeBytes(source) + 512 * 1024 * 1024)
        let staging = paths.wrapper.deletingLastPathComponent().appendingPathComponent(".outlands-activation-\(UUID().uuidString).app")
        defer { try? fm.removeItem(at: staging) }
        _ = try await Command.run("/usr/bin/ditto", [source.path, staging.path], timeout: 14400, log: log)
        try GameProcesses.requireClosed(source)
        try GameProcesses.requireClosed(paths.wrapper)
        guard try Snapshot.fingerprint(source) == snapshot else { throw InstallerError("The restored files changed during activation. Close the game and try again.") }
        try Task.checkCancellation()
        return try Transaction.promote(staging: staging, destination: paths.wrapper)
    }
    private func treeBytes(_ root: URL) throws -> Int64 {
        let rootInfo = try root.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey, .isSymbolicLinkKey])
        if rootInfo.isRegularFile == true && rootInfo.isSymbolicLink != true { return Int64(rootInfo.fileSize ?? 0) }
        var scanError: Error?
        guard let entries = fm.enumerator(at: root, includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey, .isSymbolicLinkKey], errorHandler: { _, error in scanError = error; return false }) else {
            throw InstallerError("Cannot read the game folder.")
        }
        var result: Int64 = 0
        for case let url as URL in entries {
            try Task.checkCancellation()
            let info = try url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey, .isSymbolicLinkKey])
            if info.isRegularFile == true && info.isSymbolicLink != true {
                let (next, overflow) = result.addingReportingOverflow(Int64(info.fileSize ?? 0))
                guard !overflow, next < Int64.max - 512 * 1024 * 1024 else { throw InstallerError("The game folder is too large to archive.") }
                result = next
            }
        }
        if let scanError { throw scanError }
        return result
    }
    private func requireSpace(at folder: URL, bytes: Int64) throws {
        let available = try folder.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]).volumeAvailableCapacityForImportantUsage ?? 0
        guard available >= bytes else { throw InstallerError("Not enough free space on the selected backup/restore volume. Free at least \(ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)).") }
    }
}
