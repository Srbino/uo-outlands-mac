import AppKit
import SwiftUI
import OutlandsCore
import IOKit.pwr_mgt

struct MacRequirements {
    var chip = ""
    var appleSilicon = false
    var system = ""
    var systemSupported = false
    var freeBytes: Int64 = 0
    var rosetta: Bool?
    var enoughSpace: Bool { freeBytes >= 20_000_000_000 }
    var blocking: Bool { !appleSilicon || !systemSupported || !enoughSpace }
}

enum BackupAvailability { case available, diskDisconnected, missing, checking }

@MainActor
final class AppModel: ObservableObject {
    @Published var section = "game"
    @Published var settingsRecoveryNeedsReview = false
    @Published var preview: BackupPreview?
    @Published var showBackupPreview = false
    @Published var importPlan: SettingsImportPlan?
    @Published var showSettingsImport = false
    @Published var selectedSettings: Set<String> = []
    @Published var importSearch = ""
    @Published var undoSettingsFolder: URL?
    @Published var resultURL: URL?
    @Published var resultTitle = ""
    @Published var catalogSort = "newest"
    @Published var activity = ""
    @Published var backupRecords: [BackupRecord] = []
    @Published var backupKind: BackupKind = .settings
    @Published var restoredKind: BackupKind = .full
    @Published var restoredFolder: URL?
    @Published var processes: [GameProcess] = []
    @Published var hasProcessSnapshot = false
    @Published var externalLinks: [String] = []
    @Published var busy = false
    @Published var step: InstallStep?
    @Published var message = "Ready."
    @Published var failure: String?
    @Published var finished = false
    @Published var checks: [Diagnostic] = []
    @Published var logText = ""
    @Published var acceptRosetta = false
    @Published var showReport = false
    @Published var report = ""
    @Published var updateMessage = ""
    @Published var releaseURL: URL?
    @Published var checkingUpdate = false
    @Published var stagingAvailable = false
    @Published var installed = false
    private var backupStatusGeneration = 0
    @Published var elapsed = 0
    @Published var requirements = MacRequirements()
    @Published var lastCheck: Date?
    @Published var backupStatus: [String: BackupAvailability] = [:]
    @AppStorage("checkForUpdates") var automaticUpdates = true
    let paths = Paths()
    private(set) var log: SessionLog?
    private var task: Task<Void, Never>?
    private var ticker: Task<Void, Never>?
    private var started = Date()
    private var assertion: IOPMAssertionID = 0
    var preventsIdleSleep: Bool { assertion != 0 }
    var lastBackup: BackupRecord? { backupRecords.max { $0.created < $1.created } }
    var backupReminder: Bool { backupRecords.filter { backupStatus[$0.url.path] == .available }.map(\.created).max().map { Date().timeIntervalSince($0) > 7 * 86400 } ?? true }
    private func keepAwake(_ enabled: Bool) {
        if enabled && assertion == 0 {
            IOPMAssertionCreateWithName(kIOPMAssertionTypePreventUserIdleSystemSleep as CFString,
                                       IOPMAssertionLevel(kIOPMAssertionLevelOn), "Outlands operation" as CFString, &assertion)
        } else if !enabled && assertion != 0 { IOPMAssertionRelease(assertion); assertion = 0 }
    }
    private func remember(_ url: URL, manifest: BackupManifest) {
        let old = backupRecords.first { $0.url == url }
        backupRecords.removeAll { $0.url == url }
        backupRecords.insert(BackupRecord(url: url, created: manifest.created, bytes: manifest.bytes,
                                         verified: Date(), note: old?.note ?? "", kind: manifest.scope), at: 0)
        backupRecords[0].name = old?.name
        sortCatalog(); saveCatalog()
        backupStatus[url.path] = .available
    }
    func saveCatalog() {
        if let data = try? JSONEncoder().encode(backupRecords) { UserDefaults.standard.set(data, forKey: "backupCatalog") }
    }


    init() {
        if let data = UserDefaults.standard.data(forKey: "backupCatalog"),
           let records = try? JSONDecoder().decode([BackupRecord].self, from: data) { backupRecords = records }

        if let saved = UserDefaults.standard.string(forKey: "undoSettingsFolder") { undoSettingsFolder = URL(fileURLWithPath: saved) }
        if let saved = UserDefaults.standard.string(forKey: "restoredFolder") {
            restoredFolder = URL(fileURLWithPath: saved)
            restoredKind = BackupKind(rawValue: UserDefaults.standard.string(forKey: "restoredKind") ?? "") ?? .full
        }
        Task { await refreshLocalFiles() }
        do { log = try SessionLog(directory: paths.logs) }
        catch { failure = error.localizedDescription }
        if !installed { refreshRequirements() }
        refreshBackupStatus()
    }
    func refreshLocalFiles(checkInstallation: Bool = false) async {
        let paths = paths
        let result = await Task.detached(priority: .utility) {
            (FileManager.default.fileExists(atPath: paths.wrapper.path),
             FileManager.default.fileExists(atPath: paths.staging.path),
             checkInstallation ? Wrapper.checks(paths.wrapper) : [],
             FileManager.default.fileExists(atPath: paths.wrapper.appendingPathComponent(SettingsRecovery.classicPath).deletingLastPathComponent().appendingPathComponent(".outlands-settings-recovery.json").path))
        }.value
        installed = result.0; stagingAvailable = result.1; settingsRecoveryNeedsReview = result.3
        if checkInstallation { checks = result.2; lastCheck = Date() }
    }
    func refreshRequirements() {
        var value = MacRequirements()
        var size = 0
        sysctlbyname("machdep.cpu.brand_string", nil, &size, nil, 0)
        var brand = [CChar](repeating: 0, count: max(size, 1))
        sysctlbyname("machdep.cpu.brand_string", &brand, &size, nil, 0)
        value.chip = String(cString: brand)
        #if arch(arm64)
        value.appleSilicon = true
        #endif
        let os = ProcessInfo.processInfo.operatingSystemVersion
        value.system = "macOS \(os.majorVersion).\(os.minorVersion)" + (os.patchVersion > 0 ? ".\(os.patchVersion)" : "")
        value.systemSupported = ProcessInfo.processInfo.isOperatingSystemAtLeast(OperatingSystemVersion(majorVersion: 14, minorVersion: 6, patchVersion: 0))
        value.freeBytes = requirements.freeBytes
        value.rosetta = requirements.rosetta
        requirements = value
        guard let log else { return }
        let engine = Installer(paths: paths, log: log)
        let home = paths.home
        Task {
            requirements.freeBytes = await Task.detached(priority: .utility) {
                (try? home.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]).volumeAvailableCapacityForImportantUsage) ?? 0
            }.value
            requirements.rosetta = (try? await engine.rosettaPresent()) ?? false
        }
    }
    /// Backup folders can live on disconnected or slow volumes; inspect them off the main thread.
    func refreshBackupStatus() {
        let urls = backupRecords.map(\.url)
        backupStatusGeneration += 1
        let generation = backupStatusGeneration
        Task {
            let result = await Task.detached(priority: .utility) {
                var result: [String: BackupAvailability] = [:]
                for url in urls {
                    let parts = url.pathComponents
                    if FileManager.default.fileExists(atPath: url.path) { result[url.path] = .available }
                    else if parts.count > 2, parts[1] == "Volumes", !FileManager.default.fileExists(atPath: "/Volumes/" + parts[2]) {
                        result[url.path] = .diskDisconnected
                    } else { result[url.path] = .missing }
                }
                return result
            }.value
            guard generation == backupStatusGeneration else { return }
            backupStatus = result
        }
    }
    func start(rebuild: Bool = false) {
        guard !busy, let log else { return }
        if rebuild {
            let alert = NSAlert()
            alert.messageText = "Rebuild Outlands with a backup?"
            alert.informativeText = "Close the game and launcher first. Your Windows prefix, game files and profiles will be copied into a separate installation. The original application will be kept as outlands-backup-…app after verification. Allow at least 30 GB of free space."
            alert.addButton(withTitle: "Rebuild with backup")
            alert.addButton(withTitle: "Cancel")
            guard alert.runModal() == .alertFirstButtonReturn else { return }
        }
        keepAwake(true); activity = "Installing Outlands"
        busy = true; finished = false; failure = nil; started = Date(); elapsed = 0
        ticker = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                self.logText = log.tail()
                self.elapsed = Int(Date().timeIntervalSince(self.started))
                try? await Task.sleep(nanoseconds: 1_000_000_000)
            }
        }
        let engine = Installer(paths: paths, log: log)
        let consent = acceptRosetta
        task = Task {
            do {
                try await engine.install(acceptRosettaLicense: consent, rebuild: rebuild) { [weak self] step, message in
                    self?.step = step; self?.message = message
                }
                finished = true
                message = "Installation checks passed. Open the launcher to verify startup and download the game."
            } catch is CancellationError {
                message = "Installation stopped. Your staged files are kept so you can retry."
                log.write("Installation cancelled by the user.")
            } catch {
                failure = Privacy.redact(error.localizedDescription)
                message = "Installation needs attention. Your existing game has been preserved."
                log.write("FAILED: \(error.localizedDescription)")
            }
            ticker?.cancel(); ticker = nil
            keepAwake(false); logText = log.tail()
            await refreshLocalFiles(checkInstallation: true)
            busy = false; task = nil
            if !installed { refreshRequirements() }
        }
    }
    func previewBackup() {
        guard !busy else { return }
        busy = true; elapsed = 0; failure = nil; activity = "Inspecting backup contents…"; message = "Counting current files and uncompressed data…"
        let wrapper = paths.wrapper, kind = backupKind
        task = Task {
            let worker = Task.detached(priority: .utility) {
                try kind == .settings ? GameProcesses.requireSettingsClosed(wrapper) : GameProcesses.requireClosed(wrapper)
                return try BackupPreview.inspect(wrapper: wrapper, kind: kind)
            }
            do {
                preview = try await withTaskCancellationHandler { try await worker.value } onCancel: { worker.cancel() }
                try Task.checkCancellation()
                message = "Backup preview ready."
                showBackupPreview = true
            } catch is CancellationError { message = "Backup preview stopped." }
            catch { failure = Privacy.redact(error.localizedDescription); message = "Backup preview could not be prepared." }
            busy = false; task = nil
        }
    }
    func reviewSettingsImport() {
        guard !busy, let source = restoredFolder, let log else { return }
        busy = true; elapsed = 0; failure = nil; activity = "Comparing recovered settings…"; message = "Checking files to add or replace…"
        let paths = paths
        task = Task {
            let worker = Task.detached(priority: .utility) { try await SettingsRecovery(log: log).plan(source: source, paths: paths) }
            do {
                let plan = try await withTaskCancellationHandler { try await worker.value } onCancel: { worker.cancel() }
                try Task.checkCancellation()
                importPlan = plan; selectedSettings = Set(plan.files.map(\.path)); importSearch = ""
                message = "Settings comparison ready. No changes applied."
                showSettingsImport = true
            } catch is CancellationError { message = "Settings comparison stopped." }
            catch { failure = Privacy.redact(error.localizedDescription); message = "Settings comparison could not be prepared." }
            busy = false; task = nil
        }
    }
    func applySettings() {
        guard !busy, let plan = importPlan, let log else { return }
        let selected = selectedSettings
        showSettingsImport = false
        backupTask(title: "Restoring selected settings…") { _ in
            let previous = try await SettingsRecovery(log: log).apply(plan, selected: selected, paths: self.paths) { self.activity = $0; self.message = $0 }
            self.undoSettingsFolder = previous
            UserDefaults.standard.set(previous.path, forKey: "undoSettingsFolder")
            self.resultTitle = "Settings restored. Your previous configuration is preserved for Undo."
            return self.paths.wrapper.appendingPathComponent(SettingsRecovery.classicPath)
        }
    }
    func dismissRecoveredCopy() {
        guard !busy else { return }
        restoredFolder = nil
        UserDefaults.standard.removeObject(forKey: "restoredFolder")
        UserDefaults.standard.removeObject(forKey: "restoredKind")
    }
    func recoverSettingsTransaction() {
        guard !busy, let log else { return }
        let alert = NSAlert()
        alert.messageText = "Recover the interrupted settings operation?"
        alert.informativeText = "Close Outlands first. The installer will inspect its local journal, restore an interrupted rename or retain the Undo copy for a completed operation. Ambiguous states will be left untouched."
        alert.addButton(withTitle: "Recover settings"); alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        backupTask(title: "Recovering interrupted settings…") { _ in
            let previous = try await SettingsRecovery(log: log).recoverInterrupted(paths: self.paths)
            if let previous { self.undoSettingsFolder = previous; UserDefaults.standard.set(previous.path, forKey: "undoSettingsFolder") }
            self.resultTitle = "Settings transaction recovered. Files preserved."
            return self.paths.wrapper.appendingPathComponent(SettingsRecovery.classicPath)
        }
    }
    func undoSettings() {
        guard !busy, let previous = undoSettingsFolder, let log else { return }
        let alert = NSAlert()
        alert.messageText = "Return to the previous settings?"
        alert.informativeText = "Close Outlands first. Current ClassicUO files will also be preserved, so this change can be reversed."
        alert.addButton(withTitle: "Undo settings restore"); alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        backupTask(title: "Returning to previous settings…") { _ in
            let retained = try await SettingsRecovery(log: log).undo(previous: previous, paths: self.paths)
            self.undoSettingsFolder = retained
            UserDefaults.standard.set(retained.path, forKey: "undoSettingsFolder")
            self.resultTitle = "Previous settings restored. The replaced configuration was preserved."
            return self.paths.wrapper.appendingPathComponent(SettingsRecovery.classicPath)
        }
    }
    func sortCatalog() {
        backupRecords.sort {
            switch catalogSort {
            case "oldest": return $0.created < $1.created
            case "size": return $0.bytes > $1.bytes
            default: return $0.created > $1.created
            }
        }
    }
    func createBackup() {
        guard !busy, installed else { return }
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true; panel.canChooseFiles = false
        panel.prompt = "Save backup here"
        let kind = backupKind
        panel.message = kind == .settings
            ? "Close Outlands and Razor first. Saves ClassicUO settings and character profiles, Razor profiles, scripts, macros and configuration. Game assets and Wine are excluded. Custom/external profile locations require a separate backup. Choose another disk."
            : "Close Outlands and Razor first. Saves the entire game application and Wine runtime. Choose another disk. External linked folders are not included."
        guard panel.runModal() == .OK, let folder = panel.url else { return }
        let stamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
        let destination = folder.appendingPathComponent("Outlands-\(kind == .settings ? "Settings" : "Full")-\(stamp)-\(UUID().uuidString.prefix(6)).outlandsbackup")
        backupTask(title: "Creating and verifying your backup…") { engine in
            let manifest = try await engine.create(wrapper: self.paths.wrapper, destination: destination, lockDirectory: self.paths.support, kind: kind) { self.activity = $0; self.message = $0 }
            self.remember(destination, manifest: manifest)
            self.resultTitle = kind.title + " backup saved and verified."
            return destination
        }
    }
    func chooseBackup(restore: Bool) {
        guard !busy else { return }
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true; panel.canChooseFiles = false
        panel.message = "Select an .outlandsbackup folder. Only restore backups you trust: they contain executable software and private game data."
        panel.prompt = restore ? "Choose backup" : "Verify backup"
        guard panel.runModal() == .OK, let backup = panel.url else { return }
        useBackup(backup, restore: restore)
    }
    func useBackup(_ backup: URL, restore: Bool) {
        guard !busy else { return }
        if restore {
            let destination = NSOpenPanel()
            destination.canChooseDirectories = true; destination.canChooseFiles = false
            destination.prompt = "Restore here"
            destination.message = "Restore into a new folder here. Your current installation will not be overwritten or launched."
            guard destination.runModal() == .OK, let folder = destination.url else { return }
            backupTask(title: "Verifying and restoring your backup…") { engine in
                let result = try await engine.restoreResult(backup, into: folder) { self.activity = $0; self.message = $0 }
                self.resultTitle = result.kind == .settings ? "Settings extracted. Review and apply your selected files in Backups." : "Full recovery copy extracted. Review before activation."
                self.restoredFolder = result.folder; self.restoredKind = result.kind
                UserDefaults.standard.set(result.folder.path, forKey: "restoredFolder")
                UserDefaults.standard.set(result.kind.rawValue, forKey: "restoredKind")
                return result.folder
            }
        } else {
            backupTask(title: "Checking backup integrity…") { engine in
                let manifest = try await engine.verify(backup) { self.activity = $0; self.message = $0 }
                self.remember(backup, manifest: manifest)
                return backup
            }
        }
    }
    func locateBackup(_ record: BackupRecord) {
        guard !busy else { return }
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true; panel.canChooseFiles = false
        panel.prompt = "Locate backup"
        panel.message = "The catalog remembers a path, not the backup itself. Choose the moved .outlandsbackup folder to verify it. A different backup will be added as a separate record."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        backupTask(title: "Verifying the selected backup…") { engine in
            let manifest = try await engine.verify(url) { self.activity = $0; self.message = $0 }
            if manifest.created == record.created && manifest.bytes == record.bytes && manifest.scope == record.scope {
                self.backupRecords.removeAll { $0.id == record.id }
                self.remember(url, manifest: manifest)
                if let index = self.backupRecords.firstIndex(where: { $0.url == url }) { self.backupRecords[index].note = record.note; self.saveCatalog() }
            } else { self.remember(url, manifest: manifest) }
            return url
        }
    }
    func forgetBackup(_ record: BackupRecord) {
        guard !busy else { return }
        let alert = NSAlert()
        alert.messageText = "Remove this catalog entry?"
        alert.informativeText = "Only its saved path and note will be removed from this list. No backup or game files will be deleted."
        alert.addButton(withTitle: "Remove entry"); alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        backupRecords.removeAll { $0.id == record.id }
        backupStatus.removeValue(forKey: record.id)
        saveCatalog(); refreshBackupStatus()
    }
    private func backupTask(title: String, operation: @escaping @MainActor (Backups) async throws -> URL) {
        guard !busy, let log else { return }
        keepAwake(true); activity = title
        resultURL = nil; resultTitle = ""
        busy = true; failure = nil; finished = false; step = nil; message = title
        started = Date(); elapsed = 0
        ticker = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                self.logText = log.tail(); self.elapsed = Int(Date().timeIntervalSince(self.started))
                try? await Task.sleep(nanoseconds: 1_000_000_000)
            }
        }
        task = Task {
            do {
                let result = try await operation(Backups(log: log))
                message = "Operation completed. The result is selected in Finder."
                resultURL = result
                if resultTitle.isEmpty { resultTitle = title.contains("Verif") || title.contains("Checking") ? "Backup verification completed." : "Operation completed successfully." }
                NSWorkspace.shared.activateFileViewerSelecting([result])
            } catch is CancellationError {
                message = "Backup operation cancelled. Temporary files were removed; existing backups and game files were preserved."
            } catch {
                failure = Privacy.redact(error.localizedDescription)
                message = "Backup operation needs attention. Existing backups and game files were preserved."
                log.write("BACKUP FAILED: \(error.localizedDescription)")
            }
            ticker?.cancel(); ticker = nil; keepAwake(false); logText = log.tail()
            await refreshLocalFiles()
            refreshBackupStatus()
            busy = false; task = nil
        }
    }
    func cancel() { message = "Stopping the current step safely…"; task?.cancel() }
    func diagnose() {
        guard !busy else { return }
        busy = true; failure = nil; step = nil; elapsed = 0
        activity = "Checking installation"
        message = "Checking local files and running processes…"
        let wrapper = paths.wrapper
        task = Task {
            // Directory traversal and process inspection must not block SwiftUI's main thread.
            let worker = Task.detached(priority: .userInitiated) {
                let checks = Wrapper.checks(wrapper)
                let links = try Snapshot.externalLinks(wrapper)
                let processes = try GameProcesses.owned(by: wrapper)
                try Task.checkCancellation()
                return (checks, links, processes)
            }
            do {
                let result = try await withTaskCancellationHandler {
                    try await worker.value
                } onCancel: { worker.cancel() }
                try Task.checkCancellation()
                checks = result.0; externalLinks = result.1; processes = result.2
                hasProcessSnapshot = true; lastCheck = Date()
                message = "Local checks finished. Startup, gameplay and server connectivity are not tested."
            } catch is CancellationError {
                message = "Installation checks stopped."
            } catch {
                failure = Privacy.redact(error.localizedDescription)
                message = "Installation checks could not finish."
            }
            busy = false; task = nil
        }
    }
    func openLauncher() {
        guard !busy, installed else { return }
        NSWorkspace.shared.openApplication(at: paths.wrapper, configuration: .init()) { [weak self] _, error in
            if let error { Task { @MainActor in self?.failure = error.localizedDescription } }
        }
    }
    func openFolder(_ folder: GameFolder) {
        let paths = paths
        Task {
            let result = await Task.detached(priority: .utility) {
                let url = folder.url(paths: paths)
                return (url, FileManager.default.fileExists(atPath: url.path))
            }.value
            guard result.1 else {
                failure = "This folder does not exist yet: " + Privacy.redact(result.0.path); return
            }
            if !NSWorkspace.shared.open(result.0) { failure = "Finder could not open the selected folder." }
        }
    }
    func refreshProcesses() {
        let wrapper = paths.wrapper
        Task {
            do {
                processes = try await Task.detached(priority: .utility) { try GameProcesses.owned(by: wrapper) }.value
                hasProcessSnapshot = true
            } catch { failure = Privacy.redact(error.localizedDescription) }
        }
    }
    func stopGame() {
        guard !busy, let log else { return }
        let paths = paths
        busy = true; failure = nil; activity = "Checking Outlands processes…"; step = nil
        task = Task {
            defer { keepAwake(false); busy = false; task = nil }
            do {
                processes = try await Task.detached(priority: .utility) { try GameProcesses.owned(by: paths.wrapper) }.value
                hasProcessSnapshot = true
                guard !processes.isEmpty else { message = "No Outlands processes are running."; return }
                let alert = NSAlert()
                alert.messageText = "Close all Outlands processes?"
                alert.informativeText = "Unsaved game or script changes may be lost. Unresponsive Outlands processes will be forced to quit after 3 seconds. Other Wine apps will be left running."
                alert.addButton(withTitle: "Close Outlands"); alert.addButton(withTitle: "Cancel")
                guard alert.runModal() == .alertFirstButtonReturn else { return }
                keepAwake(true); elapsed = 0; activity = "Closing Outlands…"
                let worker = Task.detached(priority: .userInitiated) {
                    let lock = try InstallLock(directory: paths.support)
                    defer { withExtendedLifetime(lock) {} }
                    return try await GameProcesses.stop(paths.wrapper, log: log)
                }
                _ = try await withTaskCancellationHandler { try await worker.value } onCancel: { worker.cancel() }
                message = "Outlands processes have stopped."
                processes = try await Task.detached(priority: .utility) { try GameProcesses.owned(by: paths.wrapper) }.value
            } catch is CancellationError { message = "Closing Outlands was stopped." }
            catch { failure = Privacy.redact(error.localizedDescription) }
            logText = log.tail()
        }
    }
    func activateRestored() {
        guard !busy, restoredKind == .full, let folder = restoredFolder else { return }
        let alert = NSAlert()
        alert.messageText = "Use the restored installation?"
        alert.informativeText = "Close Outlands first. The recovered app will be copied into place. Your current installation will be kept as a backup. Runtime compatibility is not certified; legacy Mono installations are allowed. Only activate backups you trust."
        alert.addButton(withTitle: "Activate with backup"); alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        backupTask(title: "Activating restored installation…") { engine in
            _ = try await engine.activate(restored: folder, paths: self.paths)
            self.restoredFolder = nil
            UserDefaults.standard.removeObject(forKey: "restoredFolder")
            UserDefaults.standard.removeObject(forKey: "restoredKind")
            return self.paths.wrapper
        }
    }
    func discardStaging() {
        guard !busy else { return }
        busy = true
        let paths = paths
        task = Task {
            do {
                let target = try await Task.detached(priority: .utility) {
                    let lock = try InstallLock(directory: paths.support)
                    defer { withExtendedLifetime(lock) {} }
                    try GameProcesses.requireClosed(paths.staging)
                    let source = paths.staging
                    let target = source.deletingLastPathComponent().appendingPathComponent("outlands-paused-\(UUID().uuidString).app")
                    try FileManager.default.moveItem(at: source, to: target)
                    return target
                }.value
                NSWorkspace.shared.activateFileViewerSelecting([target])
                failure = nil; message = "The previous staged copy was preserved. You can start a fresh installation."
            } catch { failure = Privacy.redact(error.localizedDescription) }
            await refreshLocalFiles()
            busy = false; task = nil
        }
    }
    func revealLogs() { NSWorkspace.shared.open(paths.logs) }
    func revealStaging() { NSWorkspace.shared.selectFile(paths.staging.path, inFileViewerRootedAtPath: paths.staging.deletingLastPathComponent().path) }
    func prepareReport() {
        // Use the last explicit diagnostic snapshot; do not scan a slow volume on the UI thread.
        report = ProblemReport.make(step: step?.rawValue ?? (activity.isEmpty ? "Application" : activity), error: failure, diagnostics: checks)
        showReport = true
    }
    func exportLog() {
        guard let log else { return }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "Outlands-diagnostics.txt"
        panel.message = "Paths and common secrets are redacted. Review the file before sharing it."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let report = ProblemReport.make(step: step?.rawValue ?? (activity.isEmpty ? "Application" : activity), error: failure, diagnostics: checks)
        Task {
            do {
                try await Task.detached(priority: .utility) {
                    try (report + "\n\n## Installer log (last 128 KB)\n" + log.tail(limit: 128 * 1024)).write(to: url, atomically: true, encoding: .utf8)
                }.value
            } catch { failure = Privacy.redact(error.localizedDescription) }
        }
    }
    func checkUpdates(automatic: Bool = false) async {
        guard !checkingUpdate else { return }
        if automatic {
            guard automaticUpdates else { return }
            let last = UserDefaults.standard.double(forKey: "lastUpdateCheck")
            guard Date().timeIntervalSince1970 - last > 86400 else { return }
        }
        checkingUpdate = true
        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: "lastUpdateCheck")
        defer { checkingUpdate = false }
        do {
            let release = try await Updates.latest()
            if let release, Updates.isNewer(release.tag_name, than: AppInfo.version) {
                updateMessage = "Installer \(release.tag_name) is available."
                releaseURL = release.html_url
            } else { updateMessage = release == nil ? "No public stable release is available yet." : "You have the latest installer." }
        } catch { updateMessage = error.localizedDescription }
    }
}
