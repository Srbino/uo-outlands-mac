import XCTest
@testable import OutlandsCore

final class LargeBackupTests: XCTestCase {
    func testRestoreRealArchiveSeparately() async throws {
        guard let archive = ProcessInfo.processInfo.environment["OUTLANDS_BACKUP_TEST_ARCHIVE"],
              let destination = ProcessInfo.processInfo.environment["OUTLANDS_TEST_ROOT"] else {
            throw XCTSkip("Set OUTLANDS_BACKUP_TEST_ARCHIVE and OUTLANDS_TEST_ROOT to verify a real restore separately.")
        }
        let root = URL(fileURLWithPath: destination)
        let engine = Backups(log: try SessionLog(directory: root.appendingPathComponent("restore-logs")))
        let result = try await engine.restore(URL(fileURLWithPath: archive), into: root)
        XCTAssertTrue(FileManager.default.fileExists(atPath: result.appendingPathComponent("outlands.app/Contents/Info.plist").path))
        print("Restored backup retained for byte comparison at \(result.path)")
    }
}
