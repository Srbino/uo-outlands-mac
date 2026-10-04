import XCTest
@testable import OutlandsCore

final class FrameworkTests: XCTestCase {
    func testRegistryRequiresInstalledMatchingArchitectureAndExactSection() {
        let registry = #"""
        [Software\\Microsoft\\NET Framework Setup\\NDP\\v4\\Full\\1033] 1
        "Install"=dword:00000001
        "Release"=dword:00080eb1
        [Software\\Wow6432Node\\Microsoft\\NET Framework Setup\\NDP\\v4\\Full] 1
        "Install"=dword:00000001
        "Release"=dword:00080eb1
        """#
        XCTAssertEqual(FrameworkInspection.release(in: registry, framework: "Framework"), 528049)
        XCTAssertNil(FrameworkInspection.release(in: registry, framework: "Framework64"))
        XCTAssertNil(FrameworkInspection.release(in: registry.replacingOccurrences(of: "00000001", with: "00000000"), framework: "Framework"))
    }

    func testMonoAndUnknownAssembliesAreNotCertifiedBySize() throws {
        let root = TestWorkspace.root.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let dll = root.appendingPathComponent("drive_c/windows/Microsoft.NET/Framework/v4.0.30319/mscorlib.dll")
        try FileManager.default.createDirectory(at: dll.deletingLastPathComponent(), withIntermediateDirectories: true)
        var pe = Data(repeating: 0, count: 256)
        pe[0] = 0x4d; pe[1] = 0x5a; pe[60] = 64; pe[64] = 0x50; pe[65] = 0x45
        pe.append("Mono development team".data(using: .utf16LittleEndian)!)
        try pe.write(to: dll)
        let mono = FrameworkInspection.check(prefix: root, framework: "Framework")
        XCTAssertFalse(mono.passed)
        XCTAssertEqual(mono.severity, .information)
        XCTAssertTrue(mono.detail.contains("Wine Mono"))
        XCTAssertTrue(mono.detail.contains("does not mean your existing game is broken"))
        pe = pe.prefix(256); pe.append(Data(repeating: 0, count: 3_000_000))
        try pe.write(to: dll)
        let unknown = FrameworkInspection.check(prefix: root, framework: "Framework")
        XCTAssertFalse(unknown.passed)
        XCTAssertEqual(unknown.severity, .warning)
        XCTAssertTrue(unknown.detail.contains("could not be identified"))
    }

    func testMicrosoftCandidateNeedsMatchingInstalledRegistryAndCLR() throws {
        let root = TestWorkspace.root.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let folder = root.appendingPathComponent("drive_c/windows/Microsoft.NET/Framework/v4.0.30319")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        var pe = Data(repeating: 0, count: 256)
        pe[0] = 0x4d; pe[1] = 0x5a; pe[60] = 64; pe[64] = 0x50; pe[65] = 0x45
        var assembly = pe
        assembly.append("Microsoft Corporation".data(using: .utf16LittleEndian)!)
        try assembly.write(to: folder.appendingPathComponent("mscorlib.dll"))
        XCTAssertFalse(FrameworkInspection.check(prefix: root, framework: "Framework").passed)
        try pe.write(to: folder.appendingPathComponent("clr.dll"))
        XCTAssertFalse(FrameworkInspection.check(prefix: root, framework: "Framework").passed)
        let registry = #"""
        [Software\\Wow6432Node\\Microsoft\\NET Framework Setup\\NDP\\v4\\Full] 1
        "Install"=dword:00000001
        "Release"=dword:00080eb1
        """#
        try registry.write(to: root.appendingPathComponent("system.reg"), atomically: true, encoding: .utf8)
        let microsoft = FrameworkInspection.check(prefix: root, framework: "Framework")
        XCTAssertTrue(microsoft.passed); XCTAssertEqual(microsoft.severity, .passed)
        XCTAssertFalse(FrameworkInspection.check(prefix: root, framework: "Framework64").passed)
        try registry.replacingOccurrences(of: "00000001", with: "00000000").write(to: root.appendingPathComponent("system.reg"), atomically: true, encoding: .utf8)
        XCTAssertFalse(FrameworkInspection.check(prefix: root, framework: "Framework").passed)
    }

    func testReadOnlyRuntimeInspectionWhenRequested() throws {
        guard let path = ProcessInfo.processInfo.environment["OUTLANDS_INSPECT_WRAPPER"] else {
            throw XCTSkip("Set OUTLANDS_INSPECT_WRAPPER for read-only inspection; no Wine is executed.")
        }
        let root = URL(fileURLWithPath: path)
        let expectMono = ProcessInfo.processInfo.environment["OUTLANDS_EXPECT_MONO"] == "1"
        for framework in ["Framework", "Framework64"] {
            let result = FrameworkInspection.check(prefix: Paths.prefix(root), framework: framework)
            print("\(result.title): \(result.detail)")
            XCTAssertEqual(result.passed, !expectMono)
            if expectMono { XCTAssertTrue(result.detail.contains("Wine Mono")); XCTAssertEqual(result.severity, .information) }
        }
    }
    /// Executes the exact installer's x86/x64 WPF gate only in an explicitly selected QA prefix.
    func testManagedRuntimeOnDisposableWrapperWhenRequested() async throws {
        guard let path = ProcessInfo.processInfo.environment["OUTLANDS_RUNTIME_TEST_WRAPPER"] else {
            throw XCTSkip("Set OUTLANDS_RUNTIME_TEST_WRAPPER to a disposable .qa wrapper.")
        }
        let wrapper = URL(fileURLWithPath: path).resolvingSymlinksInPath()
        guard wrapper.path.contains("/.qa/"), wrapper != Paths().wrapper.resolvingSymlinksInPath() else {
            XCTFail("Refusing a production or non-QA wrapper"); return
        }
        let original = try GameProcesses.owned(by: Paths().wrapper)
        let log = try SessionLog(directory: wrapper.deletingLastPathComponent().appendingPathComponent("managed-test-logs"))
        let engine = Installer(paths: Paths(home: wrapper.deletingLastPathComponent()), log: log)
        do {
            try await engine.smokeTest(wrapper)
            try await engine.managedSmokeTest(wrapper)
        } catch {
            _ = try? await GameProcesses.stop(wrapper, log: log)
            throw error
        }
        _ = try await GameProcesses.stop(wrapper, log: log)
        for process in original {
            XCTAssertEqual(GameProcesses.inspect(process.pid), process, "Production process identity must remain unchanged")
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: Paths.prefix(wrapper).appendingPathComponent("drive_c/windows/Temp/OutlandsInstallerProbe").path))
    }

}
