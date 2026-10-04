import XCTest
@testable import OutlandsCore

extension SettingsBackupTests {
    func target() throws -> Paths {
        let paths = Paths(home: root.appendingPathComponent("disposable-home"))
        let current = paths.wrapper.appendingPathComponent(SettingsBackup.base)
        try FileManager.default.createDirectory(at: current.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: root.appendingPathComponent("outlands.app/" + SettingsBackup.base), to: current)
        for relative in ["Data/Plugins/Assistant/Scripts/mining.razor", "Data/Plugins/Assistant/Macros/heal.macro"] {
            try Data("old settings".utf8).write(to: current.appendingPathComponent(relative))
        }
        try Data("game untouched".utf8).write(to: current.deletingLastPathComponent().appendingPathComponent("art.mul"))
        return paths
    }
    func recovery() throws -> SettingsRecovery { SettingsRecovery(log: try SessionLog(directory: root.appendingPathComponent("recovery-logs"))) }
    func testPreviewShowsSelectiveCountsWithoutGameAssets() throws {
        let app = try fixture()
        let preview = try BackupPreview.inspect(wrapper: app, kind: .settings)
        XCTAssertEqual(preview.scripts, 1); XCTAssertEqual(preview.macros, 2)
        XCTAssertGreaterThan(preview.profileFiles, 1)
        XCTAssertGreaterThan(preview.bytes, 0); XCTAssertLessThan(preview.bytes, 100_000)
    }
    func testSelectedSettingsApplyAndUndoPreserveUnselectedFilesAndGame() async throws {
        _ = try fixture()
        let paths = try target(), engine = try recovery()
        let plan = try await engine.plan(source: root, paths: paths)
        let script = "Data/Plugins/Assistant/Scripts/mining.razor"
        XCTAssertTrue(plan.files.contains { $0.path == script && $0.replacesExisting })
        let previous = try await engine.apply(plan, selected: [script], paths: paths)
        let current = paths.wrapper.appendingPathComponent(SettingsBackup.base)
        XCTAssertEqual(try Data(contentsOf: current.appendingPathComponent(script)), Data("private settings č".utf8))
        XCTAssertEqual(try Data(contentsOf: current.appendingPathComponent("Data/Plugins/Assistant/Macros/heal.macro")), Data("old settings".utf8))
        XCTAssertEqual(try Data(contentsOf: previous.appendingPathComponent(script)), Data("old settings".utf8))
        XCTAssertEqual(try Data(contentsOf: current.deletingLastPathComponent().appendingPathComponent("art.mul")), Data("game untouched".utf8))
        let retained = try await engine.undo(previous: previous, paths: paths)
        XCTAssertEqual(try Data(contentsOf: current.appendingPathComponent(script)), Data("old settings".utf8))
        XCTAssertEqual(try Data(contentsOf: retained.appendingPathComponent(script)), Data("private settings č".utf8))
    }
    func testSettingsSourceChangeAfterReviewIsRejected() async throws {
        _ = try fixture()
        let paths = try target(), engine = try recovery()
        let plan = try await engine.plan(source: root, paths: paths)
        let script = "Data/Plugins/Assistant/Scripts/mining.razor"
        try Data("changed".utf8).write(to: root.appendingPathComponent("outlands.app/" + SettingsBackup.base + "/" + script))
        do { _ = try await engine.apply(plan, selected: [script], paths: paths); XCTFail("Stale plan accepted") } catch {}
        XCTAssertEqual(try Data(contentsOf: paths.wrapper.appendingPathComponent(SettingsBackup.base + "/" + script)), Data("old settings".utf8))
    }
    func testFailedSettingsSwapRollsBackOriginalAndRemovesJournal() async throws {
        _ = try fixture()
        let paths = try target(), engine = try recovery()
        let plan = try await engine.plan(source: root, paths: paths)
        let parent = paths.wrapper.appendingPathComponent(SettingsBackup.base).deletingLastPathComponent()
        let script = "Data/Plugins/Assistant/Scripts/mining.razor"
        do {
            _ = try await engine.apply(plan, selected: [script], paths: paths) { message in
                if message.hasPrefix("Applying settings") {
                    let stage = try! FileManager.default.contentsOfDirectory(at: parent, includingPropertiesForKeys: nil).first { $0.lastPathComponent.hasPrefix(".ClassicUO-settings-") }!
                    try! FileManager.default.removeItem(at: stage)
                }
            }
            XCTFail("Swap should fail")
        } catch {}
        XCTAssertEqual(try Data(contentsOf: paths.wrapper.appendingPathComponent(SettingsBackup.base + "/" + script)), Data("old settings".utf8))
        XCTAssertFalse(FileManager.default.fileExists(atPath: parent.appendingPathComponent(".outlands-settings-recovery.json").path))
    }
    func testCancelledSettingsPreparationPreservesOriginal() async throws {
        _ = try fixture()
        let paths = try target(), engine = try recovery()
        let plan = try await engine.plan(source: root, paths: paths)
        let script = "Data/Plugins/Assistant/Scripts/mining.razor"
        let task = Task {
            try await engine.apply(plan, selected: [script], paths: paths) { message in
                if message.hasPrefix("Applying settings") { withUnsafeCurrentTask { $0?.cancel() } }
            }
        }
        do { _ = try await task.value; XCTFail("Must cancel") } catch is CancellationError {} catch { XCTFail("\(error)") }
        XCTAssertEqual(try Data(contentsOf: paths.wrapper.appendingPathComponent(SettingsBackup.base + "/" + script)), Data("old settings".utf8))
        let parent = paths.wrapper.appendingPathComponent(SettingsBackup.base).deletingLastPathComponent()
        XCTAssertFalse(try FileManager.default.contentsOfDirectory(atPath: parent.path).contains { $0.hasPrefix(".ClassicUO-settings-") || $0.hasPrefix("ClassicUO-before-settings-") })
    }
    func testSettingsImportRejectsRedirectedDestinationAndUnrelatedUndo() async throws {
        _ = try fixture()
        let paths = try target(), engine = try recovery()
        let scripts = paths.wrapper.appendingPathComponent(SettingsBackup.base + "/Data/Plugins/Assistant/Scripts")
        let external = root.appendingPathComponent("external-target")
        try FileManager.default.moveItem(at: scripts, to: external)
        try FileManager.default.createSymbolicLink(at: scripts, withDestinationURL: external)
        do { _ = try await engine.plan(source: root, paths: paths); XCTFail("Redirected target accepted") } catch {}
        do { _ = try await engine.undo(previous: external, paths: paths); XCTFail("Unrelated undo accepted") } catch {}
        XCTAssertEqual(try Data(contentsOf: external.appendingPathComponent("mining.razor")), Data("old settings".utf8))
    }
}

extension SettingsBackupTests {
    func testInterruptedSettingsRenameRecoversOriginal() async throws {
        _ = try fixture()
        let paths = try target(), engine = try recovery()
        let current = paths.wrapper.appendingPathComponent(SettingsBackup.base)
        let parent = current.deletingLastPathComponent()
        let previous = parent.appendingPathComponent("ClassicUO-before-settings-" + UUID().uuidString)
        let stage = parent.appendingPathComponent(".ClassicUO-settings-" + UUID().uuidString)
        try FileManager.default.copyItem(at: current, to: stage)
        try JSONEncoder().encode([current.path, previous.path, stage.path]).write(to: parent.appendingPathComponent(".outlands-settings-recovery.json"))
        try FileManager.default.moveItem(at: current, to: previous)
        let undo = try await engine.recoverInterrupted(paths: paths)
        XCTAssertNil(undo)
        XCTAssertEqual(try Data(contentsOf: current.appendingPathComponent("Data/Plugins/Assistant/Scripts/mining.razor")), Data("old settings".utf8))
        XCTAssertFalse(FileManager.default.fileExists(atPath: parent.appendingPathComponent(".outlands-settings-recovery.json").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: stage.path))
    }
    func testCompletedSettingsJournalRetainsUndoAndRejectsUnsafePaths() async throws {
        _ = try fixture()
        let paths = try target(), engine = try recovery()
        let current = paths.wrapper.appendingPathComponent(SettingsBackup.base)
        let parent = current.deletingLastPathComponent()
        let previous = parent.appendingPathComponent("ClassicUO-before-settings-" + UUID().uuidString)
        let stage = parent.appendingPathComponent(".ClassicUO-settings-" + UUID().uuidString)
        let journal = parent.appendingPathComponent(".outlands-settings-recovery.json")
        try FileManager.default.copyItem(at: current, to: previous)
        try JSONEncoder().encode([current.path, previous.path, stage.path]).write(to: journal)
        let undo = try await engine.recoverInterrupted(paths: paths)
        XCTAssertEqual(undo?.standardizedFileURL.path, previous.standardizedFileURL.path)
        try JSONEncoder().encode([current.path, root.appendingPathComponent("outside").path, stage.path]).write(to: journal)
        do { _ = try await engine.recoverInterrupted(paths: paths); XCTFail("Unsafe journal accepted") } catch {}
        XCTAssertTrue(FileManager.default.fileExists(atPath: current.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: journal.path))
    }
}
