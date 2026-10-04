import XCTest
import Darwin
@testable import OutlandsCore

final class BackupSafetyTests: XCTestCase {
    var root: URL!
    override func setUpWithError() throws {
        root = TestWorkspace.root.resolvingSymlinksInPath().appendingPathComponent("ArchiveSafety-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws { try FileManager.default.removeItem(at: root) }
    // Minimal ustar fixtures: tests control paths, types and links without an external dependency.
    struct Entry {
        let name: String
        var type: UInt8 = 48
        var link = ""
        var data = Data()
    }
    func package(_ entries: [Entry], expanded: Int64 = 1024) async throws -> URL {
        var tar = Data()
        for entry in entries {
            var header = Data(repeating: 0, count: 512)
            func put(_ value: String, _ offset: Int, _ length: Int) {
                header.replaceSubrange(offset..<(offset + min(length, value.utf8.count)),
                                       with: value.utf8.prefix(length))
            }
            put(entry.name, 0, 100)
            put("0000644", 100, 8); put("0000000", 108, 8); put("0000000", 116, 8)
            put(String(format: "%011lo", entry.data.count), 124, 12)
            put("00000000000", 136, 12)
            put("        ", 148, 8)
            header[156] = entry.type; put(entry.link, 157, 100)
            put("ustar", 257, 6); put("00", 263, 2)
            put(String(format: "%06lo", header.reduce(0) { $0 + Int($1) }) + "\0 ", 148, 8)
            tar.append(header); tar.append(entry.data)
            if entry.data.count % 512 != 0 { tar.append(Data(repeating: 0, count: 512 - entry.data.count % 512)) }
        }
        tar.append(Data(repeating: 0, count: 1024))
        let package = root.appendingPathComponent(UUID().uuidString + ".outlandsbackup")
        try FileManager.default.createDirectory(at: package, withIntermediateDirectories: false)
        let raw = package.appendingPathComponent("outlands.tar")
        try tar.write(to: raw)
        _ = try await Command.run("/usr/bin/gzip", [raw.path], timeout: 10,
                                  log: SessionLog(directory: root.appendingPathComponent("logs")), logOutput: false)
        let payload = package.appendingPathComponent("outlands.tar.gz")
        let manifest = BackupManifest(format: 1, created: Date(), installer: AppInfo.version,
                                      sha256: try Integrity.sha256(payload),
                                      bytes: Int64(try payload.resourceValues(forKeys: [.fileSizeKey]).fileSize!),
                                      expandedBytes: expanded)
        try JSONEncoder().encode(manifest).write(to: package.appendingPathComponent("manifest.json"))
        return package
    }
    var base: [Entry] { [Entry(name: "outlands.app/Contents/Info.plist", data: Data("plist".utf8))] }
    func engine() throws -> Backups { Backups(log: try SessionLog(directory: root.appendingPathComponent("logs"))) }

    func testRejectsUnsafeArchiveMembersWithoutExtraction() async throws {
        let cases: [[Entry]] = [
            base + [Entry(name: "../escape", data: Data("escape".utf8))],
            base + [Entry(name: "/tmp/escape")],
            base + [Entry(name: "outlands.app/bad\nname")],
            base + [Entry(name: "outlands.app/Contents/info.plist")],
            base + [Entry(name: "outlands.app/pipe", type: 54)],
            base + [Entry(name: "outlands.app/link", type: 49, link: "../escape")],
            base + [Entry(name: "outlands.app/link", type: 49, link: "outlands.app/other"),
                    Entry(name: "outlands.app/other", type: 49, link: "outlands.app/link")],
            base + [Entry(name: "outlands.app/link", type: 50, link: root.path),
                    Entry(name: "outlands.app/link/escape", data: Data("escape".utf8))],
            base + [Entry(name: "outlands.app/link", type: 50, link: root.path),
                    Entry(name: "outlands.app/alias", type: 49, link: "outlands.app/link")],
            [Entry(name: "outlands.app/Contents/Info.plist", type: 50, link: "/tmp/escape")]
        ]
        let engine = try engine()
        let sentinel = root.appendingPathComponent("escape")
        try Data("untouched".utf8).write(to: sentinel)
        for entries in cases {
            let backup = try await package(entries)
            do { _ = try await engine.restore(backup, into: root); XCTFail("Unsafe archive accepted") } catch {}
            XCTAssertEqual(try Data(contentsOf: sentinel), Data("untouched".utf8))
            XCTAssertFalse(try FileManager.default.contentsOfDirectory(atPath: root.path).contains { $0.hasPrefix(".outlands-restore-") || $0.hasPrefix("Outlands-restored-") })
        }
    }
    func testRejectsUnderstatedExpandedSizeAndPayloadSymlink() async throws {
        let engine = try engine()
        let backup = try await package(base, expanded: 1)
        do { _ = try await engine.verify(backup); XCTFail("Expanded size must be measured") } catch {}
        let payload = backup.appendingPathComponent("outlands.tar.gz")
        let moved = root.appendingPathComponent("moved.gz")
        try FileManager.default.moveItem(at: payload, to: moved)
        try FileManager.default.createSymbolicLink(at: payload, withDestinationURL: moved)
        do { _ = try await engine.verify(backup); XCTFail("Payload symlink must be refused") } catch {}
    }
    func testRestoreUsesVerifiedPrivateCopyAfterSourceReplacement() async throws {
        let engine = try engine()
        let backup = try await package(base)
        let restored = try await engine.restore(backup, into: root) { message in
            if message == "Restoring into a separate folder…" {
                try! Data("replacement".utf8).write(to: backup.appendingPathComponent("outlands.tar.gz"), options: .atomic)
            }
        }
        XCTAssertEqual(try Data(contentsOf: restored.appendingPathComponent("outlands.app/Contents/Info.plist")), Data("plist".utf8))
        XCTAssertFalse(FileManager.default.fileExists(atPath: restored.appendingPathComponent("payload.tar.gz").path))
    }
    func testInterruptedRestoreCleansStagingAndPreservesSource() async throws {
        let engine = try engine()
        let backup = try await package(base)
        let original = try Data(contentsOf: backup.appendingPathComponent("outlands.tar.gz"))
        let task = Task {
            try await engine.restore(backup, into: root) { message in
                if message == "Restoring into a separate folder…" {
                    withUnsafeCurrentTask { $0?.cancel() }
                }
            }
        }
        do { _ = try await task.value; XCTFail("Restore must cancel") } catch is CancellationError {} catch { XCTFail("\(error)") }
        XCTAssertEqual(try Data(contentsOf: backup.appendingPathComponent("outlands.tar.gz")), original)
        XCTAssertFalse(try FileManager.default.contentsOfDirectory(atPath: root.path).contains { $0.hasPrefix(".outlands-restore-") || $0.hasPrefix("Outlands-restored-") })
    }
    func testChangedSourceWithPreservedModificationDateIsRejected() async throws {
        let app = root.appendingPathComponent("outlands.app")
        let contents = app.appendingPathComponent("Contents")
        try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
        let file = contents.appendingPathComponent("Info.plist")
        try Data("before".utf8).write(to: file)
        let date = try file.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate!
        let destination = root.appendingPathComponent("changed.outlandsbackup")
        let engine = try engine()
        do {
            try await engine.create(wrapper: app, destination: destination, lockDirectory: root.appendingPathComponent("lock")) { message in
                if message == "Compressing the entire Outlands application…" {
                    try! Data("after!".utf8).write(to: file)
                    try! FileManager.default.setAttributes([.modificationDate: date], ofItemAtPath: file.path)
                }
            }
            XCTFail("Changing source must not produce a backup")
        } catch {}
        XCTAssertFalse(FileManager.default.fileExists(atPath: destination.path))
        XCTAssertFalse(try FileManager.default.contentsOfDirectory(atPath: root.path).contains { $0.hasPrefix(".outlands-backup-") })
    }
    func testSettingsManifestCannotSmuggleGameBinaries() async throws {
        let backup = try await package([Entry(name: "outlands.app/" + SettingsBackup.base + "/ClassicUO.exe", data: Data("binary".utf8))])
        let url = backup.appendingPathComponent("manifest.json")
        let old = try JSONDecoder().decode(BackupManifest.self, from: Data(contentsOf: url))
        let manifest = BackupManifest(format: 2, created: old.created, installer: old.installer,
                                      sha256: old.sha256, bytes: old.bytes, expandedBytes: old.expandedBytes, kind: .settings)
        try JSONEncoder().encode(manifest).write(to: url)
        do { _ = try await engine().restore(backup, into: root); XCTFail("Settings scope must restrict actual archive members") } catch {}
        XCTAssertFalse(try FileManager.default.contentsOfDirectory(atPath: root.path).contains { $0.hasPrefix("Outlands-restored-") || $0.hasPrefix(".outlands-restore-") })
    }
    func testAcceptsInternalHardLinkAndExternalSymlinkWithoutFollowingIt() async throws {
        let backup = try await package(base + [
            Entry(name: "outlands.app/hard", type: 49, link: "outlands.app/Contents/Info.plist"),
            Entry(name: "outlands.app/external", type: 50, link: "/missing/external")
        ])
        let restored = try await engine().restore(backup, into: root)
        XCTAssertEqual(try Data(contentsOf: restored.appendingPathComponent("outlands.app/hard")), Data("plist".utf8))
        XCTAssertEqual(try FileManager.default.destinationOfSymbolicLink(atPath: restored.appendingPathComponent("outlands.app/external").path), "/missing/external")
    }
}
