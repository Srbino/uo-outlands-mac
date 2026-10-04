import Foundation
import Darwin

public struct CommandResult: Sendable {
    public let status: Int32
    public let output: String
}

public enum Command {
    /// argv is passed directly to posix_spawn, never interpolated into a shell.
    /// Each command owns a process group so cancellation cannot kill another Wine app.
    public static func run(_ executable: String, _ arguments: [String] = [],
                           environment: [String: String] = [:], timeout: TimeInterval = 300,
                           log: SessionLog, allowFailure: Bool = false, logOutput: Bool = true) async throws -> CommandResult {
        try Task.checkCancellation()
        let output = log.url.deletingLastPathComponent().appendingPathComponent(".command-\(UUID().uuidString)")
        let fd = Darwin.open(output.path, O_CREAT | O_EXCL | O_RDWR | O_NOFOLLOW, 0o600)
        guard fd >= 0 else { throw InstallerError("Cannot create command output file.") }
        defer { Darwin.close(fd); try? FileManager.default.removeItem(at: output) }
        let reader = try FileHandle(forReadingFrom: output)
        defer { try? reader.close() }
        var actions: posix_spawn_file_actions_t?
        var attributes: posix_spawnattr_t?
        posix_spawn_file_actions_init(&actions)
        posix_spawnattr_init(&attributes)
        defer { posix_spawn_file_actions_destroy(&actions); posix_spawnattr_destroy(&attributes) }
        posix_spawn_file_actions_addopen(&actions, STDIN_FILENO, "/dev/null", O_RDONLY, 0)
        posix_spawn_file_actions_adddup2(&actions, fd, STDOUT_FILENO)
        posix_spawn_file_actions_adddup2(&actions, fd, STDERR_FILENO)
        posix_spawn_file_actions_addclose(&actions, fd)
        posix_spawnattr_setflags(&attributes, Int16(POSIX_SPAWN_SETPGROUP | POSIX_SPAWN_CLOEXEC_DEFAULT))
        posix_spawnattr_setpgroup(&attributes, 0)
        var env = ["HOME": FileManager.default.homeDirectoryForCurrentUser.path,
                   "PATH": "/usr/bin:/bin:/usr/sbin:/sbin", "LANG": "en_US.UTF-8", "LC_ALL": "en_US.UTF-8",
                   "USER": NSUserName(), "LOGNAME": NSUserName(), "TMPDIR": NSTemporaryDirectory()]
        env.merge(environment) { _, new in new }
        let argv = ([executable] + arguments).map { strdup($0) } + [nil]
        let envp = env.sorted { $0.key < $1.key }.map { strdup("\($0.key)=\($0.value)") } + [nil]
        defer { argv.forEach { free($0) }; envp.forEach { free($0) } }
        var pid: pid_t = 0
        let launch = argv.withUnsafeBufferPointer { args in
            envp.withUnsafeBufferPointer { vars in
                posix_spawn(&pid, executable, &actions, &attributes, args.baseAddress!, vars.baseAddress!)
            }
        }
        guard launch == 0 else { throw InstallerError("Cannot start \(URL(fileURLWithPath: executable).lastPathComponent): \(String(cString: strerror(launch))).") }
        log.write("Running \(URL(fileURLWithPath: executable).lastPathComponent) \(arguments.joined(separator: " "))")
        let started = Date()
        var status: Int32 = 0
        func drain() {
            if let data = try? reader.read(upToCount: 256 * 1024), !data.isEmpty, logOutput {
                log.write(Privacy.redact(String(decoding: data, as: UTF8.self)))
            }
        }
        while true {
            let result = waitpid(pid, &status, WNOHANG)
            if result == pid { break }
            if result < 0 { throw InstallerError("Could not read child process status.") }
            drain()
            var outputInfo = stat()
            let excessiveOutput = fstat(fd, &outputInfo) == 0 && outputInfo.st_size > 100 * 1024 * 1024
            if Task.isCancelled || Date().timeIntervalSince(started) > timeout || excessiveOutput {
                kill(-pid, SIGTERM)
                // Short grace period; then reap the owned process group, including grandchildren.
                try? await Task.sleep(nanoseconds: 300_000_000)
                kill(-pid, SIGKILL)
                while waitpid(pid, &status, 0) < 0 && errno == EINTR {}
                drain()
                if Task.isCancelled { throw CancellationError() }
                if excessiveOutput { throw InstallerError("The command produced over 100 MB of output and was stopped. Review the log before retrying.") }
                throw InstallerError("\(URL(fileURLWithPath: executable).lastPathComponent) exceeded its time limit. Check the log and retry.")
            }
            try? await Task.sleep(nanoseconds: 200_000_000)
        }
        drain()
        let h = try FileHandle(forReadingFrom: output)
        defer { try? h.close() }
        let bytes = try h.read(upToCount: 8 * 1024 * 1024) ?? Data()
        let resultText = String(decoding: bytes, as: UTF8.self)
        let exitCode = (status & 0x7f) == 0 ? (status >> 8) & 0xff : 128 + (status & 0x7f)
        guard allowFailure || exitCode == 0 else {
            throw InstallerError("\(URL(fileURLWithPath: executable).lastPathComponent) failed (code \(exitCode)). Open the log for details, then retry or prepare a problem report.")
        }
        return CommandResult(status: exitCode, output: resultText)
    }
}
