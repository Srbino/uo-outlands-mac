import XCTest
@testable import OutlandsCore

final class IntegrationTests: XCTestCase {
    /// Opt-in: network + Rosetta + a temporary Wine prefix. Never uses the user's wrapper.
    func testDownloadedRuntime() async throws {
        guard ProcessInfo.processInfo.environment["OUTLANDS_NETWORK_TESTS"] == "1" else {
            throw XCTSkip("Set OUTLANDS_NETWORK_TESTS=1 for the isolated download/Wine integration test.")
        }
        #if !arch(arm64)
        throw XCTSkip("Wine integration requires Apple Silicon.")
        #endif
        let fm = FileManager.default
        let base = URL(fileURLWithPath: ProcessInfo.processInfo.environment["OUTLANDS_TEST_ROOT"] ?? TestWorkspace.root.path)
        let root = base.appendingPathComponent("Outlands-integration-\(UUID().uuidString)")
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        let logs = URL(fileURLWithPath: ProcessInfo.processInfo.environment["OUTLANDS_TEST_LOGS"] ?? root.appendingPathComponent("logs").path)
        let log = try SessionLog(directory: logs)
        let cache = URL(fileURLWithPath: ProcessInfo.processInfo.environment["OUTLANDS_COMPONENT_CACHE"] ?? root.appendingPathComponent("cache").path)
        let downloads = Downloads(cache: cache, log: log)
        let recipe = try Recipe.bundled()
        let template = try await downloads.fetch(recipe.template)
        let engine = try await downloads.fetch(recipe.engine)
        let tricks = try await downloads.fetch(recipe.winetricks)
        try await downloads.extract(template, to: root)
        try await downloads.extract(engine, to: root)
        try await downloads.extract(tricks, to: root)
        let wrapper = root.appendingPathComponent(recipe.template.name.replacingOccurrences(of: ".tar.xz", with: ".app"))
        try fm.moveItem(at: root.appendingPathComponent("wswine.bundle"), to: wrapper.appendingPathComponent("Contents/SharedSupport/wine"))
        try Wrapper.configure(wrapper)
        let scripts = root.appendingPathComponent(recipe.winetricks.name.replacingOccurrences(of: ".tar.gz", with: "") + "/src/winetricks")
        XCTAssertTrue(try String(contentsOf: scripts).contains("load_dotnet48()"), "Pinned Winetricks must support .NET 4.8")
        let env = Wrapper.environment(wrapper)
        do {
            try await Installer(paths: Paths(home: root), log: log).initializePrefix(wrapper)
            try await Installer(paths: Paths(home: root), log: log).smokeTest(wrapper)
            _ = try await Command.run(wrapper.appendingPathComponent("Contents/SharedSupport/wine/bin/wineserver").path,
                                      ["-k"], environment: env, timeout: 20, log: log)
            try fm.removeItem(at: root)
        } catch {
            _ = try? await Command.run(wrapper.appendingPathComponent("Contents/SharedSupport/wine/bin/wineserver").path,
                                       ["-k"], environment: env, timeout: 20, log: log)
            print("Integration artifacts retained at \(root.path)")
            throw error
        }
    }
}
