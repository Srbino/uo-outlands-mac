import XCTest
@testable import OutlandsCore

final class SettingsBackupTests: XCTestCase {
    var root: URL!
    override func setUpWithError() throws {
        root = TestWorkspace.root.resolvingSymlinksInPath().appendingPathComponent("SettingsBackup-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws { try FileManager.default.removeItem(at: root) }
    func fixture(_ custom: String = "") throws -> URL {
        let app = root.appendingPathComponent("outlands.app")
        func write(_ relative: String, _ value: String) throws {
            let file = app.appendingPathComponent(relative)
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(value.utf8).write(to: file)
        }
        try write("Contents/Info.plist", "plist")
        let base = SettingsBackup.base
        try write(base + "/settings.json", "{\"profilespath\":\"\(custom)\"}")
        for path in ["Data/Profiles/account/shard/character/profile.json",
                     "Data/Profiles/account/shard/character/macros.xml",
                     "Data/Plugins/Assistant/Profiles/character.xml",
                     "Data/Plugins/Assistant/Macros/heal.macro",
                     "Data/Plugins/Assistant/Scripts/mining.razor",
                     "Data/Plugins/Assistant/counters.xml",
                     "Data/Plugins/Assistant/settings.csv",
                     "Data/Plugins/Assistant/guardlines.def",
                     "Data/Plugins/Razor/Profiles/legacy.xml",
                     "Data/Plugins/Razor/Razor.exe.config",
                     "Data/Client/friends.usr",
                     "Data/Client/MapIcons/custom.png"] {
            try write(base + "/" + path, "private settings č")
        }
        for path in ["Data/Client/JournalLogs/private.txt", "Data/Plugins/Assistant/Razor.dll", "ClassicUO.exe"] {
            try write(base + "/" + path, "excluded binary or log")
        }
        try write("Contents/SharedSupport/runtime/wine", "excluded engine")
        try write(SettingsBackup.base.replacingOccurrences(of: "/ClassicUO", with: "") + "/art.mul", "excluded game asset")
        return app
    }
    func testSettingsRoundTripExcludesGameAndEngineAndRetainsBothLayouts() async throws {
        let app = try fixture()
        let engine = Backups(log: try SessionLog(directory: root.appendingPathComponent("logs")))
        let destination = root.appendingPathComponent("settings.outlandsbackup")
        let manifest = try await engine.create(wrapper: app, destination: destination, lockDirectory: root.appendingPathComponent("lock"), kind: .settings)
        XCTAssertEqual(manifest.format, 2); XCTAssertEqual(manifest.scope, .settings)
        XCTAssertLessThan(manifest.bytes, 100_000)
        let verified = try await engine.verify(destination)
        XCTAssertEqual(verified.scope, .settings)
        let restored = try await engine.restoreResult(destination, into: root)
        XCTAssertEqual(restored.kind, .settings)
        let files = restored.folder.appendingPathComponent("outlands.app")
        XCTAssertTrue(FileManager.default.fileExists(atPath: restored.folder.appendingPathComponent("RESTORE-INSTRUCTIONS.txt").path))
        for path in ["Data/Profiles/account/shard/character/profile.json", "Data/Profiles/account/shard/character/macros.xml",
                     "Data/Plugins/Assistant/Profiles/character.xml", "Data/Plugins/Assistant/Scripts/mining.razor",
                     "Data/Plugins/Assistant/Macros/heal.macro", "Data/Plugins/Assistant/settings.csv",
                     "Data/Plugins/Assistant/guardlines.def", "Data/Plugins/Razor/Profiles/legacy.xml",
                     "Data/Plugins/Razor/Razor.exe.config", "Data/Client/friends.usr", "Data/Client/MapIcons/custom.png"] {
            XCTAssertEqual(try Data(contentsOf: files.appendingPathComponent(SettingsBackup.base + "/" + path)), Data("private settings č".utf8))
        }
        for path in ["Contents/Info.plist", "Contents/SharedSupport/runtime/wine",
                     SettingsBackup.base + "/ClassicUO.exe", SettingsBackup.base + "/Data/Client/JournalLogs",
                     SettingsBackup.base + "/Data/Plugins/Assistant/Razor.dll",
                     SettingsBackup.base.replacingOccurrences(of: "/ClassicUO", with: "") + "/art.mul"] {
            XCTAssertFalse(FileManager.default.fileExists(atPath: files.appendingPathComponent(path).path))
        }
        do {
            _ = try await engine.activate(restored: restored.folder, paths: Paths(home: root.appendingPathComponent("test-home")))
            XCTFail("Settings cannot be activated as a full app")
        } catch {}
        XCTAssertTrue(FileManager.default.fileExists(atPath: app.appendingPathComponent("Contents/Info.plist").path))
    }
    func testCustomProfilePathIsNotSilentlyOmitted() throws {
        let app = try fixture("Data/CustomProfiles")
        XCTAssertThrowsError(try SettingsBackup.selected(app))
    }
    func testRedirectedSettingsFolderIsRejected() throws {
        let app = try fixture()
        let directory = app.appendingPathComponent(SettingsBackup.base + "/Data/Profiles")
        let external = root.appendingPathComponent("external")
        try FileManager.default.moveItem(at: directory, to: external)
        try FileManager.default.createSymbolicLink(at: directory, withDestinationURL: external)
        XCTAssertThrowsError(try SettingsBackup.selected(app))
    }
    func testOldManifestAndCatalogRemainReadable() throws {
        let manifest = Data(#"{"format":1,"created":0,"installer":"0.9.0","sha256":"hash","bytes":123,"expandedBytes":456}"#.utf8)
        XCTAssertEqual(try JSONDecoder().decode(BackupManifest.self, from: manifest).scope, .full)
        let record = BackupRecord(url: root, created: Date(), bytes: 123, verified: nil, note: "keep")
        let encoded = try JSONEncoder().encode(record)
        let decoded = try JSONDecoder().decode(BackupRecord.self, from: encoded)
        XCTAssertEqual(decoded.scope, .full); XCTAssertEqual(decoded.note, "keep")
    }
}
