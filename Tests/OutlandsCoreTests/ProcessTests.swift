import XCTest
@testable import OutlandsCore

final class ProcessTests: XCTestCase {
    private func makeSleeper(_ url: URL) throws {
        // Re-signing a copied Apple platform binary can make it unlaunchable on older Macs.
        // Compile a plain fixture so the test exercises our process ownership checks.
        let source = url.deletingLastPathComponent().appendingPathComponent("fixture.c")
        try Data("#include <unistd.h>\n#include <signal.h>\nint main(void) { signal(SIGTERM, SIG_DFL); sigset_t mask; sigemptyset(&mask); sigprocmask(SIG_SETMASK, &mask, 0); sleep(30); return 0; }\n".utf8).write(to: source)
        let compiler = Process(); compiler.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
        compiler.arguments = ["clang", "-Wall", "-Wextra", "-Werror", source.path, "-o", url.path]
        try compiler.run(); compiler.waitUntilExit()
        guard compiler.terminationStatus == 0 else { throw InstallerError("Cannot compile process fixture") }
    }

    func testOnlySelectedWrapperProcessesAreStopped() async throws {
        let fm = FileManager.default
        let root = TestWorkspace.root.resolvingSymlinksInPath().appendingPathComponent(UUID().uuidString)
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }
        let app = root.appendingPathComponent("outlands.app")
        let other = root.appendingPathComponent("outlands.app-other")
        for folder in [app, other] {
            try fm.createDirectory(at: folder, withIntermediateDirectories: true)
            try makeSleeper(folder.appendingPathComponent("sleep"))
        }
        let own = Process(); own.executableURL = app.appendingPathComponent("sleep"); own.arguments = ["30"]
        let unrelated = Process(); unrelated.executableURL = other.appendingPathComponent("sleep"); unrelated.arguments = ["30"]
        try own.run(); try unrelated.run()
        defer { if own.isRunning { own.terminate() }; if unrelated.isRunning { unrelated.terminate() } }
        try await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertTrue(unrelated.isRunning, "Unrelated fixture must be alive before stopping anything")
        XCTAssertEqual(try GameProcesses.owned(by: app).map(\.pid), [own.processIdentifier])
        XCTAssertThrowsError(try GameProcesses.requireClosed(app))
        XCTAssertThrowsError(try GameProcesses.requireSettingsClosed(app))
        _ = try await GameProcesses.stop(app, log: SessionLog(directory: root.appendingPathComponent("logs")))
        own.waitUntilExit()
        XCTAssertTrue(unrelated.isRunning)
        XCTAssertTrue(try GameProcesses.owned(by: app).isEmpty)
    }
    func testBorrowedEngineWithAnotherPrefixIsNotOwned() async throws {
        let fm = FileManager.default
        let root = TestWorkspace.root.resolvingSymlinksInPath().appendingPathComponent(UUID().uuidString)
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }
        let executable = root.appendingPathComponent("wine")
        try makeSleeper(executable)
        let process = Process(); process.executableURL = executable; process.arguments = ["30"]
        process.environment = ["WINEPREFIX": "/another-app/prefix"]
        try process.run(); defer { if process.isRunning { process.terminate() } }
        try await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertTrue(try GameProcesses.owned(by: root).isEmpty)
        XCTAssertTrue(process.isRunning, "Compiled fixture must remain alive")
    }
    func testSettingsBackupDistinguishesKnownWineServicesFromApplications() {
        func process(_ name: String, executable: String = "/fixture/wine") -> GameProcess {
            GameProcess(pid: 42, executable: executable, name: name, startedSeconds: 1, startedMicroseconds: 0)
        }
        for service in ["services.exe", "winedevice.exe", "svchost.exe", "rpcss.exe", "plugplay.exe", "explorer.exe", "wineserver"] {
            XCTAssertTrue(process(service).isBackgroundService)
        }
        for application in ["ClassicUO.exe", "Outlands.exe", "Razor.exe", "cmd.exe", "unknown.exe", "wine"] {
            XCTAssertFalse(process(application).isBackgroundService)
        }
        XCTAssertFalse(process("services.exe", executable: "/fixture/custom-app").isBackgroundService)
    }
    func testWineEngineWithoutPrefixIsNeverSignaled() async throws {
        let fm = FileManager.default
        let root = TestWorkspace.root.appendingPathComponent(UUID().uuidString)
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }
        let executable = root.appendingPathComponent("wine")
        try makeSleeper(executable)
        let child = Process(); child.executableURL = executable; child.arguments = ["30"]
        child.environment = [:]
        try child.run()
        defer { if child.isRunning { child.terminate() } }
        try await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertTrue(child.isRunning, "Compiled fixture must be alive before inspecting ownership")
        XCTAssertThrowsError(try GameProcesses.owned(by: root))
        XCTAssertThrowsError(try GameProcesses.requireClosed(root))
        XCTAssertThrowsError(try GameProcesses.requireSettingsClosed(root))
        do {
            _ = try await GameProcesses.stop(root, log: SessionLog(directory: root.appendingPathComponent("logs")))
            XCTFail("Ambiguous Wine prefix must not be signaled")
        } catch {
            XCTAssertTrue(child.isRunning, "The ambiguous process must remain alive")
        }
    }
    func testSnapshotDetectsProfileChangesAndIgnoresExternalTargetContent() throws {
        let fm = FileManager.default
        let root = TestWorkspace.root.appendingPathComponent(UUID().uuidString)
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }
        let file = root.appendingPathComponent("profile.txt")
        try Data("before".utf8).write(to: file)
        let initial = try Snapshot.fingerprint(root)
        XCTAssertEqual(try Snapshot.fingerprint(root), initial)
        try Data("after and changed".utf8).write(to: file)
        XCTAssertNotEqual(try Snapshot.fingerprint(root), initial)
        try fm.createSymbolicLink(atPath: root.appendingPathComponent("broken").path, withDestinationPath: "/absent/external")
        XCTAssertNoThrow(try Snapshot.fingerprint(root))
    }
}
