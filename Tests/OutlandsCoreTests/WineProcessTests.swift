import XCTest
@testable import OutlandsCore

final class WineProcessTests: XCTestCase {
    func testStopOnlyDisposableWineWrapper() async throws {
        guard let path = ProcessInfo.processInfo.environment["OUTLANDS_PROCESS_TEST_WRAPPER"], path.contains("/.qa/") else {
            throw XCTSkip("Set OUTLANDS_PROCESS_TEST_WRAPPER to a disposable wrapper under .qa.")
        }
        let root = URL(fileURLWithPath: path)
        let original = try GameProcesses.owned(by: Paths().wrapper)
        let log = try SessionLog(directory: root.deletingLastPathComponent().appendingPathComponent("process-test-logs"))
        let child = Task {
            try await Command.run(Wrapper.wine(root).path, ["cmd", "/c", "ping -n 120 127.0.0.1"], environment: Wrapper.environment(root), timeout: 180, log: log, allowFailure: true)
        }
        for _ in 0..<50 {
            // During exec, kernel argument metadata can be temporarily unavailable.
            // Wait for a readable identity; production operations still fail closed.
            if let owned = try? GameProcesses.owned(by: root), !owned.isEmpty { break }
            try await Task.sleep(nanoseconds: 100_000_000)
        }
        XCTAssertFalse(try GameProcesses.owned(by: root).isEmpty)
        _ = try await GameProcesses.stop(root, log: log)
        _ = try? await child.value
        XCTAssertTrue(try GameProcesses.owned(by: root).isEmpty)
        for process in original { XCTAssertEqual(GameProcesses.inspect(process.pid), process, "Existing installation must remain untouched") }
    }
}
