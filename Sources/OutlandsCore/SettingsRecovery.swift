import Foundation

public struct SettingsImportFile: Identifiable, Sendable {
    public var id: String { path }
    public let path: String
    public let bytes: Int64
    public let replacesExisting: Bool
}
public struct SettingsImportPlan: Sendable {
    public let source: URL
    public let files: [SettingsImportFile]
    public let fingerprint: String
}
/// Builds a complete ClassicUO replacement beside the current directory, then swaps directories.
/// Game assets and Wine are outside ClassicUO and never copied or replaced. Previous ClassicUO
/// remains on disk for Undo, including unrelated settings and client binaries.
public actor SettingsRecovery {
    public static let classicPath = SettingsBackup.base
    private let log: SessionLog
    private let fm = FileManager.default
    public init(log: SessionLog) { self.log = log }
    private func real(_ url: URL) throws {
        guard url.standardizedFileURL == url.resolvingSymlinksInPath() else { throw InstallerError("Settings recovery cannot use redirected folders or files.") }
    }
    public func plan(source: URL, paths: Paths) throws -> SettingsImportPlan {
        let wrapper = source.appendingPathComponent("outlands.app")
        try real(wrapper)
        let base = wrapper.appendingPathComponent(SettingsBackup.base)
        let target = paths.wrapper.appendingPathComponent(SettingsBackup.base)
        try real(target)
        var files: [SettingsImportFile] = []
        func add(_ file: URL) throws {
            try Task.checkCancellation()
            let info = try file.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
            guard info.isSymbolicLink != true else { throw InstallerError("Recovered settings contain links. Copy their data separately; automatic import does not follow links.") }
            guard info.isRegularFile == true else { return }
            try real(file)
            let prefix = base.resolvingSymlinksInPath().path + "/"
            let path = file.resolvingSymlinksInPath().path
            guard path.hasPrefix(prefix) else { throw InstallerError("Recovered settings are outside their expected folder.") }
            let relative = String(path.dropFirst(prefix.count))
            guard SettingsBackup.permits(("outlands.app/" + SettingsBackup.base + "/" + relative).lowercased(), directory: false) else { throw InstallerError("Unsupported recovered settings path.") }
            let destination = target.appendingPathComponent(relative)
            try real(destination)
            files.append(SettingsImportFile(path: relative, bytes: Int64(info.fileSize ?? 0), replacesExisting: fm.fileExists(atPath: destination.path)))
        }
        for relative in try SettingsBackup.selected(wrapper) {
            let url = wrapper.appendingPathComponent(relative)
            try add(url)
            if try url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory == true {
                var failure: Error?
                guard let entries = fm.enumerator(at: url, includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey], errorHandler: { _, error in failure = error; return false }) else { throw InstallerError("Cannot read recovered settings.") }
                for case let file as URL in entries { try add(file) }
                if let failure { throw failure }
            }
        }
        guard !files.isEmpty else { throw InstallerError("No recoverable settings files were found.") }
        return SettingsImportPlan(source: source, files: files.sorted { $0.path < $1.path }, fingerprint: try SettingsBackup.fingerprint(wrapper))
    }
    public func apply(_ plan: SettingsImportPlan, selected: Set<String>, paths: Paths,
                      progress: @MainActor @Sendable (String) -> Void = { _ in }) async throws -> URL {
        let lock = try InstallLock(directory: paths.support)
        defer { withExtendedLifetime(lock) {} }
        let current = paths.wrapper.appendingPathComponent(SettingsBackup.base)
        try real(current)
        guard fm.fileExists(atPath: current.path), !selected.isEmpty, selected.isSubset(of: Set(plan.files.map(\.path))) else { throw InstallerError("Select supported settings files and an existing installation.") }
        try GameProcesses.requireSettingsClosed(paths.wrapper)
        let fresh = try self.plan(source: plan.source, paths: paths)
        guard fresh.fingerprint == plan.fingerprint else { throw InstallerError("Recovered settings changed after preview. Review them again before applying.") }
        let before = try Snapshot.fingerprint(current)
        let preview = try BackupPreview.inspect(wrapper: current, kind: .full)
        let available = try current.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]).volumeAvailableCapacityForImportantUsage ?? 0
        let incoming = try fresh.files.filter { selected.contains($0.path) }.reduce(Int64(0)) { sum, file in
            let next = sum.addingReportingOverflow(file.bytes)
            guard !next.overflow, next.partialValue < Int64.max - 512 * 1024 * 1024 else { throw InstallerError("Selected settings are too large.") }
            return next.partialValue
        }
        guard preview.bytes < Int64.max - incoming - 512 * 1024 * 1024,
              available >= preview.bytes + incoming + 512 * 1024 * 1024 else { throw InstallerError("Not enough space to prepare settings safely. Choose fewer files or free space on the game disk.") }
        let parent = current.deletingLastPathComponent()
        let stage = parent.appendingPathComponent(".ClassicUO-settings-\(UUID().uuidString)")
        let previous = parent.appendingPathComponent("ClassicUO-before-settings-\(UUID().uuidString)")
        let journal = parent.appendingPathComponent(".outlands-settings-recovery.json")
        guard !fm.fileExists(atPath: journal.path) else { throw InstallerError("A previous settings transaction needs review. Open the game folder and inspect .outlands-settings-recovery.json before continuing.") }
        defer { try? fm.removeItem(at: stage) }
        await progress("Preparing settings safely; the current files remain in place…")
        _ = try await Command.run("/usr/bin/ditto", [current.path, stage.path], timeout: 14400, log: log, logOutput: false)
        let source = plan.source.appendingPathComponent("outlands.app/" + SettingsBackup.base)
        for file in fresh.files where selected.contains(file.path) {
            try Task.checkCancellation()
            let destination = stage.appendingPathComponent(file.path)
            try real(destination)
            try fm.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
            if fm.fileExists(atPath: destination.path) { try fm.removeItem(at: destination) }
            try fm.copyItem(at: source.appendingPathComponent(file.path), to: destination)
        }
        try GameProcesses.requireSettingsClosed(paths.wrapper)
        guard try Snapshot.fingerprint(current) == before,
              try SettingsBackup.fingerprint(plan.source.appendingPathComponent("outlands.app")) == plan.fingerprint else { throw InstallerError("Settings changed during preparation. Nothing was replaced; review and retry.") }
        try Task.checkCancellation()
        await progress("Applying settings; keeping the previous configuration for Undo…")
        try Task.checkCancellation()
        try real(current)
        try GameProcesses.requireSettingsClosed(paths.wrapper)
        guard try Snapshot.fingerprint(current) == before else { throw InstallerError("Current settings changed before applying. Nothing was replaced.") }
        // Persist rename recovery information BEFORE moving the original. No cancellation mid-swap.
        try JSONEncoder().encode([current.path, previous.path, stage.path]).write(to: journal, options: .atomic)
        do { try fm.moveItem(at: current, to: previous) }
        catch { try? fm.removeItem(at: journal); throw error }
        do { try fm.moveItem(at: stage, to: current) }
        catch {
            do { try fm.moveItem(at: previous, to: current); try fm.removeItem(at: journal) }
            catch { throw InstallerError("Settings swap was interrupted. The original files are preserved; inspect .outlands-settings-recovery.json in the game folder.") }
            throw error
        }
        try? fm.removeItem(at: journal)
        log.write("Selected settings applied. Previous ClassicUO directory preserved for Undo.")
        return previous
    }
    /// Resolve an interrupted pair of renames from the bounded local journal.
    /// A pending first rename is rolled back; an already completed swap keeps its Undo copy.
    public func recoverInterrupted(paths: Paths) throws -> URL? {
        let lock = try InstallLock(directory: paths.support)
        defer { withExtendedLifetime(lock) {} }
        let current = paths.wrapper.appendingPathComponent(SettingsBackup.base)
        let parent = current.deletingLastPathComponent()
        let journal = parent.appendingPathComponent(".outlands-settings-recovery.json")
        try real(journal); try real(current)
        let handle = try FileHandle(forReadingFrom: journal)
        defer { try? handle.close() }
        guard let data = try handle.read(upToCount: 65536), data.count < 65536,
              let saved = try? JSONDecoder().decode([String].self, from: data), saved.count == 3,
              URL(fileURLWithPath: saved[0]).standardizedFileURL == current.standardizedFileURL else { throw InstallerError("Invalid settings recovery journal. No files were moved.") }
        let previous = URL(fileURLWithPath: saved[1]), stage = URL(fileURLWithPath: saved[2])
        guard previous.deletingLastPathComponent() == parent,
              stage.deletingLastPathComponent() == parent,
              previous.lastPathComponent.hasPrefix("ClassicUO-before-settings-"),
              stage.lastPathComponent.hasPrefix(".ClassicUO-settings-") || stage.lastPathComponent.hasPrefix("ClassicUO-before-settings-") else { throw InstallerError("Unsafe settings recovery locations. No files were moved.") }
        try real(previous); try real(stage)
        try GameProcesses.requireSettingsClosed(paths.wrapper)
        let hasCurrent = fm.fileExists(atPath: current.path), hasPrevious = fm.fileExists(atPath: previous.path), hasStage = fm.fileExists(atPath: stage.path)
        try Task.checkCancellation()
        if !hasCurrent && hasPrevious {
            try fm.moveItem(at: previous, to: current)
            try fm.removeItem(at: journal)
            return nil
        }
        if hasCurrent && hasPrevious && !hasStage {
            try fm.removeItem(at: journal)
            return previous
        }
        if hasCurrent && !hasPrevious && hasStage {
            try fm.removeItem(at: journal)
            return nil
        }
        throw InstallerError("Settings recovery state is ambiguous. Files were preserved; inspect the game folder before continuing.")
    }

    public func undo(previous: URL, paths: Paths) throws -> URL {
        let lock = try InstallLock(directory: paths.support)
        defer { withExtendedLifetime(lock) {} }
        let current = paths.wrapper.appendingPathComponent(SettingsBackup.base)
        guard previous.deletingLastPathComponent() == current.deletingLastPathComponent(),
              previous.lastPathComponent.hasPrefix("ClassicUO-before-settings-") else { throw InstallerError("The recovery location does not belong to this installation.") }
        try real(previous); try real(current)
        try GameProcesses.requireSettingsClosed(paths.wrapper)
        let retained = current.deletingLastPathComponent().appendingPathComponent("ClassicUO-before-settings-\(UUID().uuidString)")
        let journal = current.deletingLastPathComponent().appendingPathComponent(".outlands-settings-recovery.json")
        guard !fm.fileExists(atPath: journal.path) else { throw InstallerError("A settings transaction needs review before Undo.") }
        try Task.checkCancellation()
        try JSONEncoder().encode([current.path, retained.path, previous.path]).write(to: journal, options: .atomic)
        try fm.moveItem(at: current, to: retained)
        do { try fm.moveItem(at: previous, to: current) }
        catch { try fm.moveItem(at: retained, to: current); try? fm.removeItem(at: journal); throw error }
        try? fm.removeItem(at: journal)
        return retained
    }
}
