import Foundation

/// All fixture backups and restores stay in the checkout (or an explicit QA root).
/// Never depend on macOS ignoring a caller's TMPDIR override.
enum TestWorkspace {
    static var root: URL {
        if let path = ProcessInfo.processInfo.environment["OUTLANDS_TEST_ROOT"] {
            return URL(fileURLWithPath: path).resolvingSymlinksInPath()
        }
        return URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent(".qa/unit-tests").resolvingSymlinksInPath()
    }
}
