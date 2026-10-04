import XCTest
@testable import OutlandsCore

final class LauncherTests: XCTestCase {
    func testRegistrationOnDisposableWrapperWhenRequested() async throws {
        guard let path = ProcessInfo.processInfo.environment["OUTLANDS_LAUNCHER_TEST_WRAPPER"] else {
            throw XCTSkip("Set OUTLANDS_LAUNCHER_TEST_WRAPPER to a disposable .qa wrapper.")
        }
        let wrapper = URL(fileURLWithPath: path).resolvingSymlinksInPath()
        guard wrapper.path.contains("/.qa/"), wrapper != Paths().wrapper.resolvingSymlinksInPath() else {
            XCTFail("Refusing a production or non-QA wrapper"); return
        }
        let log = try SessionLog(directory: wrapper.deletingLastPathComponent().appendingPathComponent("registration-logs"))
        let engine = Installer(paths: Paths(home: wrapper.deletingLastPathComponent()), log: log)
        let environment = Wrapper.environment(wrapper)
        try await engine.registerLauncherDirectory(wrapper)
        let result = try await Command.run(Wrapper.wine(wrapper).path,
            ["reg", "query", #"HKLM\Software\Wow6432Node\Ultima Online Outlands"#, "/v", "InstallDir"],
            environment: environment, timeout: 30, log: log)
        XCTAssertTrue(result.output.contains(#"C:\Program Files (x86)\Ultima Online Outlands"#))
        _ = try await Command.run(wrapper.appendingPathComponent("Contents/SharedSupport/wine/bin/wineserver").path,
                                   ["-k"], environment: environment, timeout: 30, log: log)
    }
}
