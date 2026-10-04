import XCTest
@testable import OutlandsCore

private final class GitHubStub: URLProtocol {
    static var status = 200
    static var responseBody = ""
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let response = HTTPURLResponse(url: request.url!, statusCode: Self.status, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(Self.responseBody.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
final class UpdateTests: XCTestCase {
    private func session(status: Int, body: String = "") -> URLSession {
        GitHubStub.status = status; GitHubStub.responseBody = body
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [GitHubStub.self]
        return URLSession(configuration: config)
    }
    func testNoPublicReleaseIsNotAnError() async throws {
        let value = try await Updates.latest(session: session(status: 404))
        XCTAssertNil(value)
    }
    func testRateLimitHasActionableMessage() async {
        do {
            _ = try await Updates.latest(session: session(status: 429))
            XCTFail("Expected rate limit error")
        } catch { XCTAssertTrue(error.localizedDescription.contains("rate-limiting")) }
    }
    func testRejectsUntrustedReleaseURL() async {
        let body = #"{"tag_name":"v2.0.0","html_url":"https://example.com/download","draft":false,"prerelease":false}"#
        do {
            _ = try await Updates.latest(session: session(status: 200, body: body))
            XCTFail("Expected untrusted URL error")
        } catch { XCTAssertTrue(error.localizedDescription.contains("unexpected release")) }
    }
    func testValidStableRelease() async throws {
        let body = #"{"tag_name":"v2.0.0","html_url":"https://github.com/Srbino/uo-outlands-mac/releases/tag/v2.0.0","draft":false,"prerelease":false}"#
        let value = try await Updates.latest(session: session(status: 200, body: body))
        XCTAssertEqual(value?.tag_name, "v2.0.0")
    }
    func testInvalidJSONFailsInsteadOfReportingUpToDate() async {
        do {
            _ = try await Updates.latest(session: session(status: 200, body: "<html>Offline</html>"))
            XCTFail("Invalid metadata should fail")
        } catch { XCTAssertTrue(error is DecodingError) }
    }
}
