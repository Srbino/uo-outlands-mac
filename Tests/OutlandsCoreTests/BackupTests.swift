import XCTest
@testable import OutlandsCore

final class BackupTests: XCTestCase {
    var root: URL!
    override func setUpWithError() throws {
        root = TestWorkspace.root.resolvingSymlinksInPath().appendingPathComponent("Backup č test \(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws { try FileManager.default.removeItem(at: root) }
    func fixture() throws -> URL {
        let app = root.appendingPathComponent("outlands.app")
        let folder = app.appendingPathComponent("Contents/SharedSupport/prefix/drive_c/Outlands/Razor/Scripts")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data("plist".utf8).write(to: app.appendingPathComponent("Contents/Info.plist"))
        try Data("my private script\nčeský profil".utf8).write(to: folder.appendingPathComponent("mining.txt"))
        try FileManager.default.createSymbolicLink(atPath: app.appendingPathComponent("external").path, withDestinationPath: "/not-included-missing-target")
        return app
    }
    func testWholeWrapperRoundTripAndCorruption() async throws {
        let app = try fixture()
        let log = try SessionLog(directory: root.appendingPathComponent("logs"))
        let engine = Backups(log: log)
        let backup = root.appendingPathComponent("snapshot.outlandsbackup")
        try await engine.create(wrapper: app, destination: backup, lockDirectory: root.appendingPathComponent("lock"))
        let manifest = try await engine.verify(backup)
        XCTAssertEqual(manifest.format, 1)
        let restored = try await engine.restore(backup, into: root)
        let relative = "outlands.app/Contents/SharedSupport/prefix/drive_c/Outlands/Razor/Scripts/mining.txt"
        XCTAssertEqual(try Data(contentsOf: restored.appendingPathComponent(relative)), Data("my private script\nčeský profil".utf8))
        XCTAssertEqual(try FileManager.default.destinationOfSymbolicLink(atPath: restored.appendingPathComponent("outlands.app/external").path), "/not-included-missing-target")
        XCTAssertTrue(FileManager.default.fileExists(atPath: app.path))
        do {
            try await engine.create(wrapper: app, destination: backup, lockDirectory: root.appendingPathComponent("lock"))
            XCTFail("Must never overwrite a backup")
        } catch {}
        try Data("damaged".utf8).write(to: backup.appendingPathComponent("outlands.tar.gz"))
        do { _ = try await engine.restore(backup, into: root); XCTFail("Must refuse damaged data") } catch {}
        XCTAssertFalse(log.tail().contains("my private script"))
    }
    func testActivationPreservesCurrentInstallation() async throws {
        let fm = FileManager.default
        let app = try fixture()
        let wine = Wrapper.wine(app)
        try fm.createDirectory(at: wine.deletingLastPathComponent(), withIntermediateDirectories: true)
        try fm.copyItem(atPath: "/usr/bin/true", toPath: wine.path)
        var pe = Data(repeating: 0, count: 2_100_000)
        pe[0] = 0x4d; pe[1] = 0x5a; pe[60] = 64; pe[64] = 0x50; pe[65] = 0x45
        // A legacy backup without Microsoft .NET must remain recoverable.
        for path in [Paths.launcher(app)] {
            try fm.createDirectory(at: path.deletingLastPathComponent(), withIntermediateDirectories: true)
            try pe.write(to: path)
        }
        try Data().write(to: Paths.prefix(app).appendingPathComponent("system.reg"))
        let paths = Paths(home: root.appendingPathComponent("home"))
        try fm.createDirectory(at: paths.wrapper, withIntermediateDirectories: true)
        try Data("preserve old profile".utf8).write(to: paths.wrapper.appendingPathComponent("old-profile"))
        let engine = Backups(log: try SessionLog(directory: root.appendingPathComponent("logs")))
        XCTAssertTrue(Wrapper.checks(app).contains { $0.title.hasPrefix(".NET ") && !$0.passed })
        let backup = try await engine.activate(restored: root, paths: paths)
        XCTAssertNotNil(backup)
        XCTAssertEqual(try String(contentsOf: backup!.appendingPathComponent("old-profile")), "preserve old profile")
        XCTAssertTrue(fm.fileExists(atPath: Paths.launcher(paths.wrapper).path))
        XCTAssertTrue(fm.fileExists(atPath: app.path))
    }
    func testRefusesRecursiveDestinationAndCancelledBackup() async throws {
        let app = try fixture()
        let engine = Backups(log: try SessionLog(directory: root.appendingPathComponent("logs")))
        do {
            try await engine.create(wrapper: app, destination: app.appendingPathComponent("recursive.outlandsbackup"), lockDirectory: root.appendingPathComponent("lock"))
            XCTFail("Must reject recursive backup")
        } catch {}
        let destination = root.appendingPathComponent("cancelled.outlandsbackup")
        let task = Task {
            try await engine.create(wrapper: app, destination: destination, lockDirectory: root.appendingPathComponent("lock"))
        }
        task.cancel()
        do { _ = try await task.value; XCTFail("Must cancel") } catch is CancellationError {} catch { XCTFail("Unexpected error: \(error)") }
        XCTAssertFalse(FileManager.default.fileExists(atPath: destination.path))
        XCTAssertFalse(try FileManager.default.contentsOfDirectory(atPath: root.path).contains { $0.hasPrefix(".outlands-backup-") })
    }
}
