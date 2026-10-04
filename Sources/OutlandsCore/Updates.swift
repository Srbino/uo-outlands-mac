import Foundation

public struct Release: Decodable, Sendable {
    public let tag_name: String
    public let html_url: URL
    public let draft: Bool
    public let prerelease: Bool
}
public enum Updates {
    public static func numericVersion(_ text: String) -> [Int]? {
        let value = text.hasPrefix("v") ? String(text.dropFirst()) : text
        guard value.range(of: "^[0-9]+\\.[0-9]+\\.[0-9]+$", options: .regularExpression) != nil else { return nil }
        return value.split(separator: ".").compactMap { Int($0) }
    }
    public static func isNewer(_ candidate: String, than current: String) -> Bool {
        guard let lhs = numericVersion(candidate), let rhs = numericVersion(current), lhs.count == 3, rhs.count == 3 else { return false }
        return rhs.lexicographicallyPrecedes(lhs)
    }
    public static func latest(session: URLSession = .shared) async throws -> Release? {
        var request = URLRequest(url: URL(string: "https://api.github.com/repos/Srbino/uo-outlands-mac/releases/latest")!)
        request.timeoutInterval = 20
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("OutlandsInstaller/\(AppInfo.version)", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw InstallerError("No response from GitHub.") }
        if http.statusCode == 404 { return nil }
        guard http.statusCode == 200 else {
            throw InstallerError(http.statusCode == 403 || http.statusCode == 429
                ? "GitHub is rate-limiting update checks. Try again later; installation is still available."
                : "Update check failed (HTTP \(http.statusCode)). Try again later.")
        }
        let release = try JSONDecoder().decode(Release.self, from: data)
        guard !release.draft, !release.prerelease, numericVersion(release.tag_name) != nil,
              release.html_url.scheme == "https", release.html_url.host == "github.com",
              release.html_url.absoluteString == AppInfo.repository + "/releases/tag/" + release.tag_name else {
            throw InstallerError("GitHub returned an unexpected release. Check the repository's Releases page.")
        }
        return release
    }
}

public enum ProblemReport {
    public static func make(step: String, error: String?, diagnostics: [Diagnostic]) -> String {
        let os = ProcessInfo.processInfo.operatingSystemVersion
        return Privacy.redact("""
        ## What happened
        Describe what you clicked and what you expected here.

        ## Installer
        Version: \(AppInfo.version)
        macOS: \(os.majorVersion).\(os.minorVersion).\(os.patchVersion)
        Step: \(step)
        Error: \(error ?? "No installer error recorded")

        ## Checks
        Most recent local diagnostic snapshot; preparing this report does not run a new scan.
        \(diagnostics.map { "- [\($0.passed ? "x" : " ")] \($0.title) [\($0.severity.rawValue)]: \($0.detail)" }.joined(separator: "\n"))

        ## Reproduction
        1.
        2.

        Logs are not attached automatically. Review an exported log before attaching it.
        """)
    }
    public static func issueURL(body: String) -> URL {
        var components = URLComponents(string: AppInfo.repository + "/issues/new")!
        var excerpt = String(Privacy.redact(body).prefix(5000))
        while true {
            components.queryItems = [URLQueryItem(name: "title", value: "[Installer] Describe the problem"),
                                    URLQueryItem(name: "body", value: excerpt)]
            let url = components.url!
            if url.absoluteString.utf8.count <= 7000 { return url }
            excerpt = String(excerpt.prefix(max(0, excerpt.count - 200)))
        }
    }
}
