import Foundation
import Darwin

public enum InstallStep: String, CaseIterable, Sendable {
    case system = "Check your Mac"
    case download = "Download components"
    case wrapper = "Prepare the application"
    case runtime = "Set up Windows runtimes"
    case launcher = "Install Outlands launcher"
    case verify = "Verify and finish"
}

public enum DiagnosticSeverity: String, Sendable { case passed, information, warning, failure }
public struct Diagnostic: Identifiable, Sendable {
    public var id: String { title }
    public let title: String
    public let passed: Bool
    public let detail: String
    public let severity: DiagnosticSeverity
    public init(_ title: String, _ passed: Bool, _ detail: String, severity: DiagnosticSeverity? = nil) {
        self.title = title; self.passed = passed; self.detail = detail
        self.severity = severity ?? (passed ? .passed : .failure)
    }
}

public enum Wrapper {
    public static func wine(_ root: URL) -> URL { root.appendingPathComponent("Contents/SharedSupport/wine/bin/wine") }
    public static func environment(_ root: URL) -> [String: String] {
        let frameworks = root.appendingPathComponent("Contents/Frameworks").path
        let engine = root.appendingPathComponent("Contents/SharedSupport/wine").path
        return ["WINEPREFIX": Paths.prefix(root).path, "WINEDEBUG": "-all",
                "SikarugirAppWine11": "1", "CX_ROOT": engine, "WINEESYNC": "1", "WINEMSYNC": "1",
                "DYLD_FALLBACK_LIBRARY_PATH": "\(engine)/lib:\(frameworks):\(frameworks)/GStreamer.framework/Libraries:/usr/lib",
                "PATH": "\(engine)/bin:/usr/bin:/bin:/usr/sbin:/sbin"]
    }
    public static func checks(_ root: URL) -> [Diagnostic] {
        let fm = FileManager.default
        let prefix = Paths.prefix(root)
        var checks = [Diagnostic("Wrapper", fm.fileExists(atPath: root.appendingPathComponent("Contents/Info.plist").path), "Application bundle"),
            Diagnostic("Wine engine", fm.isExecutableFile(atPath: wine(root).path), "Embedded Wine executable"),
            Diagnostic("Windows prefix", fm.fileExists(atPath: prefix.appendingPathComponent("system.reg").path), "Windows registry"),
            Diagnostic("Outlands launcher", Integrity.isPE(Paths.launcher(root)), "Windows PE executable")]
        for framework in ["Framework", "Framework64"] {
            checks.append(FrameworkInspection.check(prefix: prefix, framework: framework))
        }
        let hasClient = fm.fileExists(atPath: prefix.appendingPathComponent("drive_c/Program Files (x86)/Ultima Online Outlands/ClassicUO/ClassicUO.exe").path)
        checks.append(Diagnostic("Game download", hasClient, hasClient ? "Client is present; use Verify in the launcher to check game files." : "Open the Outlands launcher to download the game."))
        return checks
    }
    /// Recovered legacy wrappers may use Mono or a different framework. Activation checks
    /// their structure, not compliance with the new installer's Microsoft runtime recipe.
    public static func activationChecks(_ root: URL) -> [Diagnostic] {
        checks(root).filter { !$0.title.hasPrefix(".NET ") && $0.title != "Game download" }
    }
    public static func configure(_ root: URL) throws {
        let url = root.appendingPathComponent("Contents/Info.plist")
        guard var plist = try PropertyListSerialization.propertyList(from: Data(contentsOf: url), format: nil) as? [String: Any] else {
            throw InstallerError("The wrapper configuration is invalid.")
        }
        for key in ["D3DMETAL", "WINEESYNC", "WINEMSYNC", "Winetricks silent", "Skip Mono"] { plist[key] = 1 }
        for key in ["DXVK", "DXMT", "D9VK", "CNC_DDRAW", "METAL_HUD", "Winetricks disable logging", "Symlinks In User Folder"] { plist[key] = 0 }
        plist["CFBundleName"] = "UO Outlands"
        plist["CFBundleIdentifier"] = "com.srbino.outlands.game"
        plist["Program Name and Path"] = AppInfo.program
        plist["WINEDEBUG"] = "-all"
        try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0).write(to: url, options: .atomic)
    }
}

/// Installation is built beside the destination. Only a verified result is promoted.
public enum Transaction {
    public static func promote(staging: URL, destination: URL, fileManager: FileManager = .default) throws -> URL? {
        var backup: URL?
        if fileManager.fileExists(atPath: destination.path) {
            let target = destination.deletingLastPathComponent().appendingPathComponent("outlands-backup-\(UUID().uuidString).app")
            try fileManager.moveItem(at: destination, to: target)
            backup = target
        }
        do { try fileManager.moveItem(at: staging, to: destination) }
        catch {
            if let backup { try fileManager.moveItem(at: backup, to: destination) }
            throw error
        }
        return backup
    }
}

public actor Installer {
    public let paths: Paths
    public let log: SessionLog
    private let fm = FileManager.default
    public init(paths: Paths, log: SessionLog) { self.paths = paths; self.log = log }

    public func rosettaPresent() async throws -> Bool {
        let result = try await Command.run("/usr/bin/arch", ["-x86_64", "/usr/bin/true"], timeout: 20, log: log, allowFailure: true)
        return result.status == 0
    }

    public func install(acceptRosettaLicense: Bool, rebuild: Bool = false,
                        progress: @MainActor @Sendable @escaping (InstallStep, String) async -> Void) async throws {
        try assertSafeLocations()
        let lock = try InstallLock(directory: paths.support)
        defer { withExtendedLifetime(lock) {} }
        let recipe = try Recipe.bundled()
        let root = paths.staging
        await progress(.system, "Checking macOS, disk space and Rosetta…")
        try Task.checkCancellation()
        #if !arch(arm64)
        throw InstallerError("This installer requires an Apple Silicon Mac. Download the arm64 application.")
        #endif
        guard ProcessInfo.processInfo.isOperatingSystemAtLeast(OperatingSystemVersion(majorVersion: 14, minorVersion: 6, patchVersion: 0)) else {
            throw InstallerError("macOS 14.6 or later is required by Sikarugir.")
        }
        guard getuid() != 0 else { throw InstallerError("Open the installer as your normal macOS user, not as root.") }
        let capacity = try paths.home.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]).volumeAvailableCapacityForImportantUsage ?? 0
        guard capacity >= (rebuild ? 30 : 20) * 1_000_000_000 else {
            throw InstallerError("Free at least \(rebuild ? 30 : 20) GB on your home disk, then retry. A rebuild keeps a backup of your current game.")
        }
        try assertSafeLocations()
        let exists = fm.fileExists(atPath: paths.wrapper.path)
        guard !exists || rebuild else { throw InstallerError("Outlands is already installed. Use Open launcher, Diagnostics, or Rebuild with backup.") }
        if exists { try await requireGameClosed() }
        let originalSnapshot = exists ? try Snapshot.fingerprint(Paths.prefix(paths.wrapper)) : nil
        if !(try await rosettaPresent()) {
            guard acceptRosettaLicense else { throw InstallerError("Rosetta is required. Review Apple's licence and enable the Rosetta option before installing.") }
            _ = try await Command.run("/usr/sbin/softwareupdate", ["--install-rosetta", "--agree-to-license"], timeout: 600, log: log)
            guard try await rosettaPresent() else { throw InstallerError("Rosetta could not be verified. Finish installation in macOS, then retry.") }
        }
        let marker = root.appendingPathComponent(".outlands-installer.json")
        let signature = "outlands-v1:\(recipe.revision):\(recipe.engine.sha256):\(recipe.template.sha256):\(recipe.winetricks.sha256):\(exists ? "rebuild" : "new"):\(originalSnapshot ?? "fresh")"
        if fm.fileExists(atPath: root.path) {
            guard (try? String(contentsOf: marker, encoding: .utf8)) == signature else {
                throw InstallerError("An older or unrecognised staging folder exists at \(root.path). Move it aside in Finder before retrying; it has not been deleted.")
            }
        }
        await progress(.download, "Downloading and checking SHA-256. Slow connections can take several minutes…")
        let downloads = Downloads(cache: paths.cache, log: log)
        let engine = try await downloads.fetch(recipe.engine)
        let template = try await downloads.fetch(recipe.template)
        let tricksArchive = try await downloads.fetch(recipe.winetricks)
        try Task.checkCancellation()
        await progress(.wrapper, "Building a separate copy. Your existing installation stays in place…")
        if !fm.fileExists(atPath: root.path) {
            let work = paths.cache.appendingPathComponent("extract-\(UUID().uuidString)")
            defer { try? fm.removeItem(at: work) }
            try await downloads.extract(template, to: work)
            let templateName = recipe.template.name.replacingOccurrences(of: ".tar.xz", with: ".app")
            let source = work.appendingPathComponent(templateName)
            guard fm.isExecutableFile(atPath: source.appendingPathComponent("Contents/MacOS/Sikarugir").path) else {
                throw InstallerError("The downloaded template has an unsupported layout.")
            }
            try await downloads.extract(engine, to: work)
            try await downloads.extract(tricksArchive, to: work)
            let tricksName = recipe.winetricks.name.replacingOccurrences(of: ".tar.gz", with: "")
            let tricks = work.appendingPathComponent(tricksName + "/src/winetricks")
            try fm.copyItem(at: tricks, to: source.appendingPathComponent("Contents/Resources/winetricks"))
            try fm.moveItem(at: work.appendingPathComponent("wswine.bundle"), to: source.appendingPathComponent("Contents/SharedSupport/wine"))
            if exists {
                // Copy all game files and profiles; no symlinks into the original prefix are introduced.
                _ = try await Command.run("/usr/bin/ditto", [Paths.prefix(paths.wrapper).path, Paths.prefix(source).path], timeout: 1800, log: log)
            }
            try signature.write(to: source.appendingPathComponent(".outlands-installer.json"), atomically: true, encoding: .utf8)
            try fm.createDirectory(at: root.deletingLastPathComponent(), withIntermediateDirectories: true)
            try fm.moveItem(at: source, to: root)
        }
        try Wrapper.configure(root)
        // Scope quarantine removal to the downloaded, checksum-verified wrapper only.
        _ = try await Command.run("/usr/bin/xattr", ["-drs", "com.apple.quarantine", root.path], log: log)
        await progress(.runtime, "Preparing .NET. This can take 15–45 minutes. Complete any Microsoft setup windows that appear…")
        do {
            if !fm.fileExists(atPath: Paths.prefix(root).appendingPathComponent("system.reg").path) {
                try await initializePrefix(root)
            }
            guard fm.fileExists(atPath: Paths.prefix(root).appendingPathComponent("system.reg").path) else {
                throw InstallerError("Wine did not create a Windows prefix. Review the runtime log.")
            }
            try await smokeTest(root)
            if !(try await dotNetReady(root)) {
                // Winetricks uses this marker rather than checking the installed runtime.
                // A cancelled/incorrect prior setup must not make every retry skip .NET.
                let runtimeMarker = Paths.prefix(root).appendingPathComponent("drive_c/windows/dotnet48.installed.workaround")
                if fm.fileExists(atPath: runtimeMarker.path) { try fm.removeItem(at: runtimeMarker) }
                for package in ["remove_mono", "dotnet20sp2", "dotnet40", "dotnet48"] {
                    try Task.checkCancellation()
                    await progress(.runtime, "Installing \(package). Complete any Microsoft setup windows; this step may take 30 minutes…")
                    try await winetricks(root, package, timeout: 3600)
                }
                guard try await dotNetReady(root) else {
                    throw InstallerError(".NET 4.8 could not be verified. The staged installation is preserved. Review the log and retry.")
                }
            }
            try await winetricks(root, "win10", timeout: 300)
            let windows = try await Command.run(Wrapper.wine(root).path, ["cmd", "/c", "ver"], environment: Wrapper.environment(root), timeout: 90, log: log)
            guard windows.output.contains("10.0") else { throw InstallerError("Wine did not switch to Windows 10 mode.") }
            try await stopWine(root)
            try fixFonts(root)
            await progress(.launcher, "Downloading the official Outlands launcher…")
            let exe = Paths.launcher(root)
            if !Integrity.isPE(exe) {
                try fm.createDirectory(at: exe.deletingLastPathComponent(), withIntermediateDirectories: true)
                let partial = exe.deletingLastPathComponent().appendingPathComponent("Outlands-\(UUID().uuidString).partial")
                defer { try? fm.removeItem(at: partial) }
                try await downloads.download(AppInfo.launcherURL, to: partial)
                guard Integrity.isPE(partial) else { throw InstallerError("The server did not return a valid Windows launcher. Retry later.") }
                if fm.fileExists(atPath: exe.path) { try fm.removeItem(at: exe) }
                try fm.moveItem(at: partial, to: exe)
            }
            try await registerLauncherDirectory(root)
            await progress(.verify, "Verifying the Windows runtime before finishing…")
            try await smokeTest(root)
            guard try await dotNetReady(root) else { throw InstallerError("The final .NET runtime check failed.") }
            try await managedSmokeTest(root)
            try await stopWine(root)
            try Task.checkCancellation()
            if exists {
                try await requireGameClosed()
                guard try Snapshot.fingerprint(Paths.prefix(paths.wrapper)) == originalSnapshot else {
                    throw InstallerError("Your original game changed during setup. It has not been replaced. Move the staged copy aside and start a fresh rebuild to include your latest profiles.")
                }
            }
            let receipt = try JSONEncoder().encode(recipe)
            try receipt.write(to: root.appendingPathComponent("outlands-install-receipt.json"), options: .atomic)
            let backup = try Transaction.promote(staging: root, destination: paths.wrapper)
            if let backup { log.write("Original installation preserved at \(backup.path)") }
            log.write("Launcher ready. Game assets still need to be downloaded and verified by the official launcher.")
        } catch {
            // Cancellation is cleared in a detached cleanup task; only this staging prefix is stopped.
            let cleanupLog = log
            await Task.detached {
                _ = try? await Command.run(root.appendingPathComponent("Contents/SharedSupport/wine/bin/wineserver").path,
                                          ["-k"], environment: Wrapper.environment(root), timeout: 15, log: cleanupLog)
            }.value
            throw error
        }
    }

    private func assertSafeLocations() throws {
        for url in [paths.support, paths.cache, paths.wrapper, paths.staging] {
            let home = paths.home.resolvingSymlinksInPath().path + "/"
            guard url.resolvingSymlinksInPath().path.hasPrefix(home) else {
                throw InstallerError("Installation folders must stay inside your home directory. Move redirected folders back before installing.")
            }
        }
        for root in [paths.wrapper, paths.staging] where fm.fileExists(atPath: root.path) {
            for suffix in ["", "Contents", "Contents/SharedSupport", "Contents/SharedSupport/prefix", "Contents/SharedSupport/prefix/drive_c", "Contents/SharedSupport/prefix/drive_c/windows", "Contents/SharedSupport/prefix/drive_c/windows/Microsoft.NET", "Contents/SharedSupport/prefix/drive_c/windows/Temp", "Contents/SharedSupport/prefix/drive_c/Program Files (x86)", "Contents/SharedSupport/prefix/drive_c/Program Files (x86)/Ultima Online Outlands"] {
                let url = suffix.isEmpty ? root : root.appendingPathComponent(suffix)
                if (try? url.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) == true {
                    throw InstallerError("An installation folder is a symbolic link. It will not be modified: \(url.path)")
                }
            }
        }
    }
    private func requireGameClosed() async throws {
        try GameProcesses.requireClosed(paths.wrapper)
    }
    private func winetricks(_ root: URL, _ package: String, timeout: TimeInterval) async throws {
        var env = Wrapper.environment(root)
        env["WINE"] = Wrapper.wine(root).path
        env["WINESERVER"] = root.appendingPathComponent("Contents/SharedSupport/wine/bin/wineserver").path
        // macOS strips DYLD_* at system shell boundaries. The Sikarugir fork restores this internally.
        env["WINETRICKS_FALLBACK_LIBRARY_PATH"] = env["DYLD_FALLBACK_LIBRARY_PATH"]
        env["WINETRICKS_LATEST_VERSION_CHECK"] = "disabled"
        env["WINETRICKS_STATS_REPORT"] = "0"
        env["WINETRICKS_GUI"] = "none"
        env["W_CACHE"] = paths.cache.appendingPathComponent("winetricks").path
        env["PATH"] = root.appendingPathComponent("Contents/Configure.app/Contents/Resources").path + ":" + (env["PATH"] ?? "/usr/bin:/bin")
        _ = try await Command.run("/bin/sh", [root.appendingPathComponent("Contents/Resources/winetricks").path, "--unattended", package],
                                  environment: env, timeout: timeout, log: log)
    }
    // Sikarugir's CLI can wait for unrelated Wine servers. Bootstrap this prefix directly.
    public func initializePrefix(_ root: URL) async throws {
        var env = Wrapper.environment(root)
        env["WINEDLLOVERRIDES"] = "mscoree,mshtml="
        _ = try await Command.run(Wrapper.wine(root).path, ["wineboot", "--init"], environment: env, timeout: 600, log: log)
        try await stopWine(root)
    }
    /// The launcher must know the directory before its first deployment. Without this key,
    /// the current launcher tries to copy itself into a nonexistent nested directory and exits.
    public func registerLauncherDirectory(_ root: URL) async throws {
        guard Integrity.isPE(Paths.launcher(root)) else { throw InstallerError("Cannot register a missing or invalid launcher.") }
        let directory = "C:" + (AppInfo.program as NSString).deletingLastPathComponent.replacingOccurrences(of: "/", with: "\\")
        _ = try await Command.run(Wrapper.wine(root).path,
                                  ["reg", "add", #"HKLM\Software\Wow6432Node\Ultima Online Outlands"#,
                                   "/v", "InstallDir", "/t", "REG_SZ", "/d", directory, "/f"],
                                  environment: Wrapper.environment(root), timeout: 90, log: log)
    }
    public func smokeTest(_ root: URL) async throws {
        let result = try await Command.run(Wrapper.wine(root).path, ["cmd", "/c", "echo OUTLANDS_RUNTIME_OK"],
                                          environment: Wrapper.environment(root), timeout: 120, log: log)
        guard result.output.contains("OUTLANDS_RUNTIME_OK") else { throw InstallerError("Wine could not run a Windows command.") }
    }
    func managedSmokeTest(_ root: URL) async throws {
        let folder = Paths.prefix(root).appendingPathComponent("drive_c/windows/Temp/OutlandsInstallerProbe")
        try fm.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: folder) }
        let source = """
        using System;
        using System.Reflection;
        class Probe {
            [STAThread] static void Main() {
                Assembly.Load("PresentationFramework, Version=4.0.0.0, Culture=neutral, PublicKeyToken=31bf3856ad364e35");
                Console.WriteLine("OUTLANDS_DOTNET_OK");
            }
        }
        """
        try source.write(to: folder.appendingPathComponent("probe.cs"), atomically: true, encoding: .utf8)
        for (framework, platform) in [("Framework", "x86"), ("Framework64", "x64")] {
            let compiler = Paths.prefix(root).appendingPathComponent("drive_c/windows/Microsoft.NET/\(framework)/v4.0.30319/csc.exe")
            _ = try await Command.run(Wrapper.wine(root).path,
                [compiler.path, "/nologo", "/platform:\(platform)", "/out:C:\\windows\\Temp\\OutlandsInstallerProbe\\probe-\(platform).exe",
                 "C:\\windows\\Temp\\OutlandsInstallerProbe\\probe.cs"], environment: Wrapper.environment(root), timeout: 120, log: log)
            let result = try await Command.run(Wrapper.wine(root).path, [folder.appendingPathComponent("probe-\(platform).exe").path],
                                               environment: Wrapper.environment(root), timeout: 120, log: log)
            guard result.output.contains("OUTLANDS_DOTNET_OK") else {
                throw InstallerError("The \(platform) .NET/WPF runtime could not execute a managed program. Retry or prepare a problem report.")
            }
        }
    }
    private func dotNetReady(_ root: URL) async throws -> Bool {
        let files = Wrapper.checks(root).filter { $0.title.hasPrefix(".NET") }.allSatisfy(\.passed)
        guard files else { return false }
        let result = try await Command.run(Wrapper.wine(root).path,
            ["reg", "query", "HKLM\\Software\\Microsoft\\NET Framework Setup\\NDP\\v4\\Full", "/v", "Release", "/reg:32"],
            environment: Wrapper.environment(root), timeout: 90, log: log, allowFailure: true)
        guard result.status == 0,
              let range = result.output.range(of: "0x[0-9a-fA-F]+", options: .regularExpression),
              let value = Int(result.output[range].dropFirst(2), radix: 16) else { return false }
        return value >= 528040
    }
    private func stopWine(_ root: URL) async throws {
        let server = root.appendingPathComponent("Contents/SharedSupport/wine/bin/wineserver").path
        _ = try await Command.run(server, ["-k"], environment: Wrapper.environment(root), timeout: 30, log: log)
        _ = try await Command.run(server, ["-w"], environment: Wrapper.environment(root), timeout: 30, log: log)
    }
    private func fixFonts(_ root: URL) throws {
        for name in ["system.reg", "user.reg"] {
            let file = Paths.prefix(root).appendingPathComponent(name)
            guard fm.fileExists(atPath: file.path) else { continue }
            let original = try String(contentsOf: file, encoding: .utf8)
            let cleaned = original.components(separatedBy: "\n").filter { !$0.lowercased().hasSuffix(".ttc\"") }.joined(separator: "\n")
            if original != cleaned { try cleaned.write(to: file, atomically: true, encoding: .utf8) }
        }
    }
}
