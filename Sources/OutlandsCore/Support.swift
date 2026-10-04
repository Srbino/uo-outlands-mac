import Foundation
import CryptoKit
import Darwin

public enum AppInfo {
    public static let version = "0.9.0"
    public static let channel = "beta"
    public static let repository = "https://github.com/Srbino/uo-outlands-mac"
    public static let launcherURL = URL(string: "https://patch.uooutlands.com/download")!
    public static let program = "/Program Files (x86)/Ultima Online Outlands/Outlands.exe"
}

public struct InstallerError: LocalizedError, Sendable {
    public let message: String
    public var errorDescription: String? { message }
    public init(_ message: String) { self.message = message }
}

public struct Asset: Codable, Sendable {
    public let name: String
    public let url: URL
    public let sha256: String
    public let size: Int64
}
public struct Recipe: Codable, Sendable {
    public let revision: Int
    public let verifiedAt: String
    public let engine: Asset
    public let template: Asset
    public let winetricks: Asset
    public static func bundled() throws -> Recipe {
        guard let url = Bundle.main.url(forResource: "recipe", withExtension: "json") ?? (Bundle.main.bundleURL.pathExtension == "app" ? nil : Bundle.module.url(forResource: "recipe", withExtension: "json")) else {
            throw InstallerError("The installer is missing its component manifest. Download it again.")
        }
        return try JSONDecoder().decode(Recipe.self, from: Data(contentsOf: url))
    }
}

public struct Paths: Sendable {
    public let home: URL
    public init(home: URL = FileManager.default.homeDirectoryForCurrentUser) { self.home = home }
    public var support: URL { home.appendingPathComponent("Library/Application Support/OutlandsInstaller") }
    public var cache: URL { home.appendingPathComponent("Library/Caches/OutlandsInstaller") }
    public var logs: URL { home.appendingPathComponent("Library/Logs/OutlandsInstaller") }
    public var wrapper: URL { home.appendingPathComponent("Applications/Sikarugir/outlands.app") }
    public var staging: URL { home.appendingPathComponent("Applications/Sikarugir/.outlands-installing.app") }
    public static func prefix(_ wrapper: URL) -> URL { wrapper.appendingPathComponent("Contents/SharedSupport/prefix") }
    public static func launcher(_ wrapper: URL) -> URL { prefix(wrapper).appendingPathComponent("drive_c" + AppInfo.program) }
}

public enum Integrity {
    public static func sha256(_ file: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: file)
        defer { try? handle.close() }
        var hash = SHA256()
        // Foundation reads may autorelease NSData. Drain each chunk even when callers
        // hash many files synchronously without returning to an application run loop.
        while true {
            try Task.checkCancellation()
            let count = try autoreleasepool {
                let chunk = try handle.read(upToCount: 1024 * 1024) ?? Data()
                hash.update(data: chunk)
                return chunk.count
            }
            if count == 0 { break }
        }
        return hash.finalize().map { String(format: "%02x", $0) }.joined()
    }
    public static func verify(_ file: URL, asset: Asset) throws {
        let size = try file.resourceValues(forKeys: [.fileSizeKey]).fileSize
        guard Int64(size ?? 0) == asset.size, try sha256(file) == asset.sha256 else {
            throw InstallerError("The download of \(asset.name) failed its integrity check. Retry to download a fresh copy.")
        }
    }
    public static func isPE(_ file: URL) -> Bool {
        guard let h = try? FileHandle(forReadingFrom: file) else { return false }
        defer { try? h.close() }
        guard let header = try? h.read(upToCount: 64), header.count == 64,
              header[0] == 0x4d, header[1] == 0x5a else { return false }
        let offset = header[60..<64].enumerated().reduce(UInt64(0)) { $0 | UInt64($1.element) << ($1.offset * 8) }
        guard offset >= 64, offset < 128 * 1024 * 1024 else { return false }
        try? h.seek(toOffset: offset)
        return (try? h.read(upToCount: 4)) == Data([0x50, 0x45, 0, 0])
    }
    public static func validateArchiveListing(_ text: String) throws {
        let names = text.split(separator: "\n")
        guard !names.isEmpty else { throw InstallerError("The component archive is empty.") }
        for name in names {
            guard !name.hasPrefix("/"), !name.split(separator: "/").contains("..") else {
                throw InstallerError("The component archive contains an unsafe path.")
            }
        }
    }
}

/// Never collect environment variables, hostnames, game profiles or credentials.
public enum Privacy {
    public static func redact(_ text: String, home: String = FileManager.default.homeDirectoryForCurrentUser.path) -> String {
        var value = text.replacingOccurrences(of: home, with: "~")
        for (pattern, replacement) in [
            (#"/Users/[^/\s]+"#, "/Users/<user>"),
            (#"(?i)([A-Z]:\\{1,2}users\\{1,2})[^\\\r\n]+"#, "$1<user>"),
            (#"(?i)(authorization\s*[:=]\s*)([^\r\n]+)"#, "$1<redacted>"),
            (#"(?i)((?:token|password|passwd|secret|api[_-]?key)\s*[:=]\s*)[^\s&]+"#, "$1<redacted>"),
            (#"\b(?:github_pat_|gh[pousr]_)[A-Za-z0-9_]+"#, "<redacted>"),
            (#"[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}"#, "<email>")
        ] {
            value = value.replacingOccurrences(of: pattern, with: replacement, options: .regularExpression)
        }
        return value
    }
}

public final class SessionLog: @unchecked Sendable {
    public let url: URL
    private let lock = NSLock()
    public init(directory: URL) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let timestamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
        url = directory.appendingPathComponent("session-\(timestamp)-\(UUID().uuidString).log")
        guard FileManager.default.createFile(atPath: url.path, contents: nil, attributes: [.posixPermissions: 0o600]) else {
            throw InstallerError("Cannot create the installation log. Check your home folder permissions.")
        }
    }
    public func write(_ text: String) {
        lock.lock(); defer { lock.unlock() }
        let fd = Darwin.open(url.path, O_WRONLY | O_APPEND)
        guard fd >= 0 else { return }
        defer { Darwin.close(fd) }
        let data = Data(("\n[\(ISO8601DateFormatter().string(from: Date()))] \(Privacy.redact(text))\n").utf8)
        data.withUnsafeBytes { bytes in _ = Darwin.write(fd, bytes.baseAddress, bytes.count) }
    }
    public func tail(limit: Int = 24000) -> String {
        guard let h = try? FileHandle(forReadingFrom: url) else { return "" }
        defer { try? h.close() }
        let end = (try? h.seekToEnd()) ?? 0
        try? h.seek(toOffset: end > UInt64(limit) ? end - UInt64(limit) : 0)
        return Privacy.redact(String(decoding: (try? h.readToEnd()) ?? Data(), as: UTF8.self))
    }
}

/// Advisory lock released by the kernel on crashes; no stale PID files.
public final class InstallLock {
    private let fd: Int32
    public init(directory: URL) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        fd = Darwin.open(directory.appendingPathComponent("install.lock").path, O_CREAT | O_RDWR | O_NOFOLLOW, 0o600)
        guard fd >= 0 else { throw InstallerError("Cannot create the installation lock.") }
        guard flock(fd, LOCK_EX | LOCK_NB) == 0 else {
            Darwin.close(fd)
            throw InstallerError("Another installation is running. Close the other installer and try again.")
        }
    }
    deinit { flock(fd, LOCK_UN); Darwin.close(fd) }
}
