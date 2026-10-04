import XCTest
@testable import OutlandsCore

final class FullInstallTests: XCTestCase {
    /// Explicit opt-in only: installs Windows prerequisites into a disposable, isolated home.
    /// This does not open the game or accept Rosetta's licence on a developer's Mac.
    func testCompleteInstallationPipeline() async throws {
        guard ProcessInfo.processInfo.environment["OUTLANDS_FULL_INSTALL_TESTS"] == "1" else {
            throw XCTSkip("Set OUTLANDS_FULL_INSTALL_TESTS=1 to test the complete installer in isolation.")
        }
        let fm = FileManager.default
        let base = URL(fileURLWithPath: ProcessInfo.processInfo.environment["OUTLANDS_TEST_ROOT"] ?? TestWorkspace.root.path)
        let home = base.appendingPathComponent("Outlands-full-test-\(UUID().uuidString)")
        try fm.createDirectory(at: home, withIntermediateDirectories: true)
        let paths = Paths(home: home)
        let logFolder = URL(fileURLWithPath: ProcessInfo.processInfo.environment["OUTLANDS_TEST_LOGS"] ?? paths.logs.path)
        let log = try SessionLog(directory: logFolder)
        if let cache = ProcessInfo.processInfo.environment["OUTLANDS_COMPONENT_CACHE"] {
            try fm.createDirectory(at: paths.cache.deletingLastPathComponent(), withIntermediateDirectories: true)
            try fm.copyItem(at: URL(fileURLWithPath: cache), to: paths.cache)
        }
        let engine = Installer(paths: paths, log: log)
        do {
            try await engine.install(acceptRosettaLicense: false) { step, message in log.write("\(step.rawValue): \(message)") }
            let checks = Wrapper.checks(paths.wrapper).filter { $0.title != "Game download" }
            XCTAssertTrue(checks.allSatisfy(\.passed), "Installed runtime and launcher must pass all local checks")
            let registration = try await Command.run(Wrapper.wine(paths.wrapper).path,
                ["reg", "query", #"HKLM\Software\Wow6432Node\Ultima Online Outlands"#, "/v", "InstallDir"],
                environment: Wrapper.environment(paths.wrapper), timeout: 30, log: log)
            XCTAssertTrue(registration.output.contains(#"C:\Program Files (x86)\Ultima Online Outlands"#))
            _ = try await Command.run(paths.wrapper.appendingPathComponent("Contents/SharedSupport/wine/bin/wineserver").path,
                ["-k"], environment: Wrapper.environment(paths.wrapper), timeout: 30, log: log)
            XCTAssertFalse(fm.fileExists(atPath: paths.staging.path))
            XCTAssertTrue(fm.fileExists(atPath: paths.wrapper.appendingPathComponent("outlands-install-receipt.json").path))
            if ProcessInfo.processInfo.environment["OUTLANDS_KEEP_TEST_INSTALL"] == "1" {
                print("Verified clean install retained at \(home.path)")
            } else { try fm.removeItem(at: home) }
        } catch {
            print("Full-install artifacts retained at \(home.path)")
            print(log.tail(limit: 8000))
            throw error
        }
    }
}
