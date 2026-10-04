import Foundation

public struct Downloads: Sendable {
    public let cache: URL
    public let log: SessionLog
    public init(cache: URL, log: SessionLog) { self.cache = cache; self.log = log }
    public func fetch(_ asset: Asset) async throws -> URL {
        guard asset.url.scheme == "https", asset.url.host == "github.com",
              asset.url.path.hasPrefix("/Sikarugir-App/"),
              asset.name == URL(fileURLWithPath: asset.name).lastPathComponent,
              asset.sha256.range(of: "^[a-f0-9]{64}$", options: .regularExpression) != nil else {
            throw InstallerError("Invalid component manifest.")
        }
        try FileManager.default.createDirectory(at: cache, withIntermediateDirectories: true)
        let target = cache.appendingPathComponent(asset.sha256 + "-" + asset.name)
        if FileManager.default.fileExists(atPath: target.path) {
            if (try? Integrity.verify(target, asset: asset)) != nil {
                log.write("Using verified cached component: \(asset.name)")
                return target
            }
            try FileManager.default.removeItem(at: target)
        }
        let partial = cache.appendingPathComponent(UUID().uuidString + ".partial")
        defer { try? FileManager.default.removeItem(at: partial) }
        try await download(asset.url, to: partial)
        try Task.checkCancellation()
        try Integrity.verify(partial, asset: asset)
        try FileManager.default.moveItem(at: partial, to: target)
        return target
    }
    public func download(_ url: URL, to target: URL) async throws {
        guard url.scheme == "https" else { throw InstallerError("Only HTTPS downloads are allowed.") }
        _ = try await Command.run("/usr/bin/curl", ["--fail", "--location", "--show-error", "--silent",
            "--proto", "=https", "--proto-redir", "=https", "--connect-timeout", "20",
            "--max-time", "1800", "--retry", "3", "--retry-delay", "2", "--retry-max-time", "1800",
            "--speed-limit", "1024", "--speed-time", "90", "--output", target.path, url.absoluteString],
            timeout: 1900, log: log)
    }
    public func extract(_ archive: URL, to destination: URL) async throws {
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        let listing = try await Command.run("/usr/bin/tar", ["-tf", archive.path], log: log, logOutput: false)
        try Integrity.validateArchiveListing(listing.output)
        // bsdtar's default path/symlink protections remain enabled (never use -P).
        _ = try await Command.run("/usr/bin/tar", ["-xf", archive.path, "-C", destination.path,
                                                     "--no-same-owner"], log: log)
    }
}
