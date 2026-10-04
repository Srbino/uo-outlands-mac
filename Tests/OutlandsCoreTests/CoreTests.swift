import XCTest
@testable import OutlandsCore

final class CoreTests: XCTestCase {
    private var temporary: URL!
    override func setUpWithError() throws {
        temporary = TestWorkspace.root.appendingPathComponent("Outlands tests ' č \(UUID().uuidString)")
        try FileManager.default.createDirectory(at: temporary, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws { try FileManager.default.removeItem(at: temporary) }
    func testRecipeUsesPinnedHTTPSComponents() throws {
        let recipe = try Recipe.bundled()
        for asset in [recipe.engine, recipe.template, recipe.winetricks] {
            XCTAssertEqual(asset.url.scheme, "https")
            XCTAssertEqual(asset.url.host, "github.com")
            XCTAssertEqual(asset.sha256.count, 64)
            XCTAssertGreaterThan(asset.size, 100_000)
        }
    }
    func testChecksumRejectsTruncatedOrCorruptDownloads() throws {
        let url = temporary.appendingPathComponent("download")
        try Data("abc".utf8).write(to: url)
        XCTAssertEqual(try Integrity.sha256(url), "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
        let asset = Asset(name: "a", url: URL(string: "https://github.com/Sikarugir-App/a")!, sha256: try Integrity.sha256(url), size: 3)
        XCTAssertNoThrow(try Integrity.verify(url, asset: asset))
        try Data("abd".utf8).write(to: url)
        XCTAssertThrowsError(try Integrity.verify(url, asset: asset))
        try Data("ab".utf8).write(to: url)
        XCTAssertThrowsError(try Integrity.verify(url, asset: asset))
    }
    func testArchiveTraversalIsRejected() throws {
        for name in ["../outside", "valid/../../outside", "/tmp/outside", ""] {
            XCTAssertThrowsError(try Integrity.validateArchiveListing(name))
        }
        XCTAssertNoThrow(try Integrity.validateArchiveListing("./Template.app/\nTemplate.app/Contents/Info.plist\n"))
    }
    func testHTMLAndFakeMZAreNotExecutables() throws {
        let url = temporary.appendingPathComponent("Outlands.exe")
        for bytes in [Data("<html>Service unavailable</html>".utf8), Data("MZnot-a-real-exe".utf8)] {
            try bytes.write(to: url); XCTAssertFalse(Integrity.isPE(url))
        }
        var pe = Data(repeating: 0, count: 128)
        pe[0] = 0x4d; pe[1] = 0x5a; pe[60] = 64; pe[64] = 0x50; pe[65] = 0x45
        try pe.write(to: url); XCTAssertTrue(Integrity.isPE(url))
    }
    func testPromotionPreservesExistingProfiles() throws {
        let old = temporary.appendingPathComponent("outlands.app")
        let staged = temporary.appendingPathComponent("staged.app")
        try FileManager.default.createDirectory(at: old, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: staged, withIntermediateDirectories: true)
        try Data("valuable profile".utf8).write(to: old.appendingPathComponent("profile"))
        try Data("new installation".utf8).write(to: staged.appendingPathComponent("new"))
        let backup = try XCTUnwrap(Transaction.promote(staging: staged, destination: old))
        XCTAssertEqual(try String(contentsOf: backup.appendingPathComponent("profile")), "valuable profile")
        XCTAssertTrue(FileManager.default.fileExists(atPath: old.appendingPathComponent("new").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: staged.path))
    }
    func testFailedPromotionRollsBackOriginal() throws {
        let old = temporary.appendingPathComponent("outlands.app")
        try FileManager.default.createDirectory(at: old, withIntermediateDirectories: true)
        try Data("profile".utf8).write(to: old.appendingPathComponent("profile"))
        XCTAssertThrowsError(try Transaction.promote(staging: temporary.appendingPathComponent("missing"), destination: old))
        XCTAssertEqual(try String(contentsOf: old.appendingPathComponent("profile")), "profile")
    }
    func testInstallLockPreventsConcurrentWritesAndReleases() throws {
        var first: InstallLock? = try InstallLock(directory: temporary)
        XCTAssertNotNil(first)
        XCTAssertThrowsError(try InstallLock(directory: temporary))
        first = nil
        XCTAssertNoThrow(try InstallLock(directory: temporary))
    }
    func testRedactionAndIssueEncoding() throws {
        let input = "/Users/alice/Library/file token=secret123 password=abc Authorization: Bearer xyz\ncontact person@example.com ghp_abcd12345"
        let text = Privacy.redact(input, home: "/Users/alice")
        for privateValue in ["alice", "secret123", "abc", "Bearer xyz", "person@example.com", "ghp_abcd12345"] {
            XCTAssertFalse(text.contains(privateValue), privateValue)
        }
        XCTAssertFalse(Privacy.redact(#"C:\users\Alice\Desktop\log"#).contains("Alice"))
        let url = ProblemReport.issueURL(body: "Error & details # č\nnext line")
        let query = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems)
        XCTAssertEqual(query.first { $0.name == "body" }?.value, "Error & details # č\nnext line")
        XCTAssertEqual(url.host, "github.com")
    }
    func testIssueURLBoundsEncodedUnicode() {
        let url = ProblemReport.issueURL(body: String(repeating: "č🚀&", count: 5000))
        XCTAssertLessThanOrEqual(url.absoluteString.utf8.count, 7000)
    }
    func testSemanticVersionComparison() {
        XCTAssertTrue(Updates.isNewer("v1.10.0", than: "1.9.9"))
        XCTAssertFalse(Updates.isNewer("v1.0.0", than: "1.0.0"))
        XCTAssertFalse(Updates.isNewer("v0.9.0", than: "1.0.0"))
        XCTAssertFalse(Updates.isNewer("v2.0.0-beta", than: "1.0.0"))
        XCTAssertFalse(Updates.isNewer("invalid", than: "1.0.0"))
    }
    func testCommandArgumentsAreNotShellCode() async throws {
        let log = try SessionLog(directory: temporary)
        let value = "space ' č $(touch /tmp/should-not-exist) ; &"
        let result = try await Command.run("/usr/bin/printf", ["%s", value], log: log)
        XCTAssertEqual(result.output, value)
        XCTAssertEqual(result.status, 0)
    }
    func testCommandFailureAndTimeout() async throws {
        let log = try SessionLog(directory: temporary)
        do {
            _ = try await Command.run("/usr/bin/false", log: log)
            XCTFail("Failure was swallowed")
        } catch { XCTAssertTrue(error.localizedDescription.contains("code 1")) }
        let started = Date()
        do {
            _ = try await Command.run("/bin/sleep", ["60"], timeout: 0.3, log: log)
            XCTFail("Timeout was swallowed")
        } catch { XCTAssertTrue(error.localizedDescription.contains("time limit")) }
        XCTAssertLessThan(Date().timeIntervalSince(started), 5)
    }
    func testCancellationStopsOwnedCommand() async throws {
        let log = try SessionLog(directory: temporary)
        let task = Task { try await Command.run("/bin/sleep", ["60"], log: log) }
        try await Task.sleep(nanoseconds: 300_000_000)
        task.cancel()
        do { _ = try await task.value; XCTFail("Cancellation was swallowed") }
        catch { XCTAssertTrue(error is CancellationError) }
    }
    func testPrivateCommandOutputIsNotLogged() async throws {
        let log = try SessionLog(directory: temporary)
        _ = try await Command.run("/usr/bin/printenv", ["PRIVATE_TEST_VALUE"], environment: ["PRIVATE_TEST_VALUE": "sensitivevalue"], log: log, logOutput: false)
        XCTAssertFalse(log.tail().contains("sensitivevalue"))
    }
    func testDiagnosticsDoNotModifyIncompleteWrapper() throws {
        let root = temporary.appendingPathComponent("missing.app")
        XCTAssertFalse(Wrapper.checks(root).contains { $0.passed })
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.path))
    }
}
