import Foundation
import Darwin

public struct GameProcess: Identifiable, Sendable, Equatable {
    public var id: Int32 { pid }
    public let pid: Int32
    public let executable: String
    public let name: String
    public var isBackgroundService: Bool {
        let engine = URL(fileURLWithPath: executable).lastPathComponent.lowercased()
        return ["wine", "wine64", "wine-preloader", "wine64-preloader", "wineserver"].contains(engine) &&
            ["services.exe", "winedevice.exe", "svchost.exe", "rpcss.exe", "plugplay.exe", "explorer.exe", "wineserver"].contains(name.lowercased())
    }
    public let startedSeconds: UInt64
    public let startedMicroseconds: UInt64
}

/// Process identity comes from the kernel, not a name substring or a reusable PID alone.
public enum GameProcesses {
    public static func inspect(_ pid: Int32) -> GameProcess? {
        var info = proc_bsdinfo()
        guard proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, Int32(MemoryLayout<proc_bsdinfo>.size)) == MemoryLayout<proc_bsdinfo>.size,
              info.pbi_uid == getuid(), pid != getpid() else { return nil }
        var path = [CChar](repeating: 0, count: 4 * Int(MAXPATHLEN))
        guard proc_pidpath(pid, &path, UInt32(path.count)) > 0 else { return nil }
        let name = withUnsafeBytes(of: info.pbi_name) { String(decoding: $0.prefix { $0 != 0 }, as: UTF8.self) }
        return GameProcess(pid: pid, executable: String(cString: path), name: name, startedSeconds: info.pbi_start_tvsec,
                           startedMicroseconds: info.pbi_start_tvusec)
    }
    public static func owned(by wrapper: URL) throws -> [GameProcess] {
        let root = wrapper.resolvingSymlinksInPath().path + "/"
        let bytes = proc_listallpids(nil, 0)
        guard bytes >= 0 else { throw InstallerError("Cannot inspect running processes. Close the game before continuing.") }
        var pids = [Int32](repeating: 0, count: Int(bytes) + 128)
        let count = proc_listallpids(&pids, Int32(pids.count * MemoryLayout<Int32>.size))
        guard count >= 0, count < pids.count else { throw InstallerError("Process list changed. Try again.") }
        return try pids.prefix(Int(count)).compactMap(inspect).filter {
            guard URL(fileURLWithPath: $0.executable).resolvingSymlinksInPath().path.hasPrefix(root) else { return false }
            // A different wrapper may explicitly borrow this engine. Never stop its prefix.
            if let prefix = winePrefix($0.pid) {
                return URL(fileURLWithPath: prefix).resolvingSymlinksInPath() == Paths.prefix(wrapper).resolvingSymlinksInPath()
            }
            // Executable location alone cannot identify a borrowed Wine engine's prefix.
            if isWineEngine($0) {
                // Exiting Wine children can disappear between kernel identity and args reads.
                guard inspect($0.pid) == $0 else { return false }
                throw InstallerError("Cannot verify the Windows prefix for Wine process PID \($0.pid). Its ownership is ambiguous; it will not be signaled. Close that application manually and retry.")
            }
            return true
        }
    }
    private static func isWineEngine(_ process: GameProcess) -> Bool {
        ["wine", "wine64", "wine-preloader", "wine64-preloader", "wineserver"].contains(URL(fileURLWithPath: process.executable).lastPathComponent.lowercased())
    }
    private static func signalIdentityMatches(_ process: GameProcess, wrapper: URL) -> Bool {
        guard inspect(process.pid) == process else { return false }
        if let prefix = winePrefix(process.pid) {
            return URL(fileURLWithPath: prefix).resolvingSymlinksInPath() == Paths.prefix(wrapper).resolvingSymlinksInPath()
        }
        return !isWineEngine(process)
    }
    private static func winePrefix(_ pid: Int32) -> String? {
        var mib: [Int32] = [CTL_KERN, KERN_PROCARGS2, pid]
        var size = 0
        guard sysctl(&mib, 3, nil, &size, nil, 0) == 0, size > 4, size <= 4 * 1024 * 1024 else { return nil }
        var buffer = [UInt8](repeating: 0, count: size)
        guard sysctl(&mib, 3, &buffer, &size, nil, 0) == 0 else { return nil }
        let argc = buffer.withUnsafeBytes { $0.loadUnaligned(as: Int32.self) }
        guard argc >= 0 else { return nil }
        var i = 4
        while i < size && buffer[i] != 0 { i += 1 }
        while i < size && buffer[i] == 0 { i += 1 }
        for _ in 0..<argc {
            while i < size && buffer[i] != 0 { i += 1 }
            i += 1
        }
        while i < size {
            let start = i
            while i < size && buffer[i] != 0 { i += 1 }
            let entry = String(decoding: buffer[start..<min(i, size)], as: UTF8.self)
            if entry.hasPrefix("WINEPREFIX=") { return String(entry.dropFirst(11)) }
            i += 1
        }
        return nil
    }
    public static func requireClosed(_ wrapper: URL) throws {
        let processes = try owned(by: wrapper)
        guard processes.isEmpty else {
            throw InstallerError("\(processes.count) Wine processes are still running for this installation, including background services. This operation requires a closed Windows prefix. Use Close processes and retry; settings-only backups allow known background services.")
        }
    }
    /// Settings live outside Wine's registry. Idle Wine services do not write these files.
    /// Unknown processes are treated as possible writers; before/after snapshots still apply.
    public static func requireSettingsClosed(_ wrapper: URL) throws {
        let writers = try owned(by: wrapper).filter { !$0.isBackgroundService }
        guard writers.isEmpty else {
            let details = writers.prefix(5).map { "PID \($0.pid) · \($0.name)" }.joined(separator: ", ")
            throw InstallerError("The game, launcher or another application in this Wine prefix is still running (\(details)). Close it before backing up settings, then retry.")
        }
    }
    /// Stops only executables physically inside this wrapper. Never calls killall/pkill.
    public static func stop(_ wrapper: URL, log: SessionLog) async throws -> Int {
        let initial = try owned(by: wrapper)
        for process in initial where signalIdentityMatches(process, wrapper: wrapper) { _ = kill(process.pid, SIGTERM) }
        log.write("Requested termination of \(initial.count) Outlands processes.")
        for _ in 0..<30 {
            if try owned(by: wrapper).isEmpty { return initial.count }
            try await Task.sleep(nanoseconds: 100_000_000)
        }
        // Include Wine children that appeared while the launcher was shutting down.
        let remaining = try owned(by: wrapper)
        for process in remaining where signalIdentityMatches(process, wrapper: wrapper) { _ = kill(process.pid, SIGKILL) }
        for _ in 0..<30 {
            if try owned(by: wrapper).isEmpty { return initial.count }
            try await Task.sleep(nanoseconds: 100_000_000)
        }
        throw InstallerError("Some Outlands processes did not exit. No unrelated Wine applications were stopped. Try again or inspect Activity Monitor.")
    }
}
