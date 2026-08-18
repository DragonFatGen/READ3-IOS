import Foundation
import XCTest
@testable import LegadoCore

final class HTTPCookieSessionTests: XCTestCase {
    func testLegacyCodableCookieDefaultsToDomainCookie() throws {
        let data = Data(#"{"name":"id","value":"1","domain":"example.invalid","path":"/","isSecure":false,"isHTTPOnly":false}"#.utf8)
        let cookie = try JSONDecoder().decode(LegadoCore.HTTPCookie.self, from: data)
        XCTAssertFalse(cookie.isHostOnly)
        XCTAssertTrue(cookie.matches(try url("https://sub.example.invalid/")))
    }

    func testDomainHostOnlyPathSecureAndHTTPOnlyMetadata() throws {
        let hostOnly = HTTPCookie(
            name: "host", value: "1", domain: "example.invalid",
            path: "/books", isSecure: true, isHTTPOnly: true, isHostOnly: true
        )
        XCTAssertTrue(hostOnly.matches(try url("https://example.invalid/books/1")))
        XCTAssertFalse(hostOnly.matches(try url("https://sub.example.invalid/books/1")))
        XCTAssertFalse(hostOnly.matches(try url("http://example.invalid/books/1")))
        XCTAssertFalse(hostOnly.matches(try url("https://example.invalid/bookstore")))
        XCTAssertTrue(hostOnly.isHTTPOnly)

        let domain = HTTPCookie(name: "domain", value: "1", domain: "example.invalid")
        XCTAssertTrue(domain.matches(try url("https://sub.example.invalid/")))
    }

    func testSetCookieParserSupportsCombinedHeadersExpiresMaxAgeAndEquals() throws {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let header = "token=a=b==; pAtH=/books; hTtPoNlY, expiresCookie=1; "
            + "Expires=Wed, 09 Jun 2038 10:18:14 GMT; sEcUrE\n"
            + "short=1; mAx-AgE=60; dOmAiN=.example.invalid"
        let cookies = SetCookieParser().parse(
            header, responseURL: try url("https://example.invalid/books/index"), now: now
        )

        XCTAssertEqual(cookies.map(\.name), ["token", "expiresCookie", "short"])
        XCTAssertEqual(cookies[0].value, "a=b==")
        XCTAssertEqual(cookies[0].path, "/books")
        XCTAssertTrue(cookies[0].isHostOnly)
        XCTAssertTrue(cookies[0].isHTTPOnly)
        XCTAssertTrue(cookies[1].isSecure)
        XCTAssertNotNil(cookies[1].expires)
        XCTAssertEqual(cookies[2].expires, now.addingTimeInterval(60))
        XCTAssertFalse(cookies[2].isHostOnly)
    }

    func testMaxAgeZeroDeletesAndReplacementUsesNameDomainPath() async throws {
        let store = InMemoryHTTPCookieStore()
        let target = try url("https://example.invalid/a/page")
        try await store.store([
            HTTPCookie(name: "id", value: "root", domain: "example.invalid", path: "/"),
            HTTPCookie(name: "id", value: "path", domain: "example.invalid", path: "/a")
        ], for: target, sourceIdentifier: "source-a")
        try await store.store([
            HTTPCookie(name: "id", value: "new", domain: "example.invalid", path: "/a")
        ], for: target, sourceIdentifier: "source-a")

        let replaced = try await store.cookies(for: target, sourceIdentifier: "source-b")
        XCTAssertEqual(replaced.map(\.value), ["new", "root"])

        let deletion = try XCTUnwrap(SetCookieParser().parse(
            "id=; Path=/a; Max-Age=0", responseURL: target
        ).first)
        try await store.store([deletion], for: target, sourceIdentifier: "source-a")
        let afterDeletion = try await store.cookies(for: target, sourceIdentifier: "source-b")
        XCTAssertEqual(afterDeletion.map(\.value), ["root"])
    }

    func testExpiredCookiesAreRemovedAndSourceRemovalUsesOwnershipNotVisibility() async throws {
        let store = InMemoryHTTPCookieStore()
        let target = try url("https://same.example.invalid/")
        try await store.store([
            HTTPCookie(
                name: "expired", value: "x", domain: "same.example.invalid",
                expires: Date(timeIntervalSince1970: 1)
            ),
            HTTPCookie(name: "shared", value: "1", domain: "same.example.invalid")
        ], for: target, sourceIdentifier: "source-a")

        let shared = try await store.cookies(for: target, sourceIdentifier: "source-b")
        XCTAssertEqual(shared.map(\.name), ["shared"])
        try await store.removeAll(sourceIdentifier: "source-a")
        let removed = try await store.cookies(for: target, sourceIdentifier: "source-b")
        XCTAssertTrue(removed.isEmpty)
    }

    func testSourceAndOptionCookiePriorityMatchesAnalyzeURL() async throws {
        let store = InMemoryHTTPCookieStore()
        let target = try url("https://example.invalid/path")
        try await store.store([
            HTTPCookie(name: "a", value: "1", domain: "example.invalid"),
            HTTPCookie(name: "b", value: "2", domain: "example.invalid")
        ], for: target, sourceIdentifier: "source")
        let request = try await RequestBuilder(cookieStore: store).build(
            #"https://example.invalid/path,{"headers":{"Cookie":"c=5; d=6"}}"#,
            sourceHeader: #"{"Cookie":"b=3; c=4"}"#,
            context: RequestBuildContext(sourceIdentifier: "source")
        )
        XCTAssertEqual(request.headers["Cookie"], "a=1; b=2; c=5; d=6")
    }

    func testRedirectStoresCookieBeforeNextHopAndFinalResponsePersistsAutomatically() async throws {
        let start = try url("https://example.invalid/start")
        let next = try url("https://example.invalid/next")
        let redirectCookie = HTTPCookie(
            name: "token", value: "abc", domain: "example.invalid", isHostOnly: true
        )
        let transport = RedirectCookieTransport(start: start, next: next, cookie: redirectCookie)
        let store = InMemoryHTTPCookieStore()
        let client = CookieSessionHTTPClient(transport: transport, cookieStore: store)

        let response = try await client.send(HTTPRequest(
            url: start, sessionIdentifier: "source-a"
        ))

        XCTAssertEqual(response.finalURL, next)
        XCTAssertEqual(response.redirects.count, 1)
        let nextRequestCookie = await transport.nextRequestCookie
        XCTAssertEqual(nextRequestCookie, "token=abc")
        let persisted = try await store.cookies(for: next, sourceIdentifier: "source-b")
        XCTAssertEqual(persisted.map(\.value), ["abc"])
    }

    func testConcurrentStoresDoNotLoseCookies() async throws {
        let store = InMemoryHTTPCookieStore()
        let target = try url("https://example.invalid/")
        await withTaskGroup(of: Void.self) { group in
            for index in 0..<40 {
                group.addTask {
                    try? await store.store([
                        HTTPCookie(
                            name: "c\(index)", value: "\(index)", domain: "example.invalid"
                        )
                    ], for: target, sourceIdentifier: "source")
                }
            }
        }
        let cookies = try await store.cookies(for: target, sourceIdentifier: nil)
        XCTAssertEqual(cookies.count, 40)
    }

    private func url(_ value: String) throws -> URL {
        try XCTUnwrap(URL(string: value))
    }
}

private actor RedirectCookieTransport: HTTPClient {
    let start: URL
    let next: URL
    let cookie: LegadoCore.HTTPCookie
    private(set) var nextRequestCookie: String?

    init(start: URL, next: URL, cookie: LegadoCore.HTTPCookie) {
        self.start = start
        self.next = next
        self.cookie = cookie
    }

    func send(_ request: HTTPRequest) async throws -> HTTPResponse {
        if request.url == start {
            return HTTPResponse(
                statusCode: 302,
                headers: HTTPHeaders(["Location": next.absoluteString]),
                data: Data(),
                finalURL: start,
                cookies: [cookie]
            )
        }
        nextRequestCookie = request.headers["Cookie"]
        return HTTPResponse(statusCode: 200, data: Data("ok".utf8), finalURL: next)
    }
}
