import Foundation
import LegadoCore
import XCTest
@testable import LegadoIOS

final class PersistentHTTPCookieStoreTests: XCTestCase {
    func testEncodeDecodeAndRestartRestoresPersistentAndSessionCookies() async throws {
        let persistence = FakeCookiePersistence()
        let first = PersistentHTTPCookieStore(persistence: persistence)
        let target = try url("https://example.invalid/account")
        try await first.store([
            HTTPCookie(name: "session", value: "abc", domain: "example.invalid"),
            HTTPCookie(
                name: "lasting", value: "yes", domain: "example.invalid",
                expires: Date().addingTimeInterval(3_600)
            )
        ], for: target, sourceIdentifier: "source-a")

        let restored = PersistentHTTPCookieStore(persistence: persistence)
        let cookies = try await restored.cookies(for: target, sourceIdentifier: "source-b")

        XCTAssertEqual(Set(cookies.map(\.name)), ["session", "lasting"])
    }

    func testExpiredCookieIsNotRestored() async throws {
        let collection = HTTPCookieCollection(records: [StoredHTTPCookie(
            cookie: HTTPCookie(
                name: "expired", value: "x", domain: "example.invalid",
                expires: Date(timeIntervalSince1970: 1)
            ),
            sourceIdentifier: "source-a"
        )])
        let persistence = FakeCookiePersistence(data: try JSONEncoder().encode(collection))
        let store = PersistentHTTPCookieStore(persistence: persistence)

        let cookies = try await store.cookies(
            for: try url("https://example.invalid/"), sourceIdentifier: "source-a"
        )

        XCTAssertTrue(cookies.isEmpty)
        let persistedData = await persistence.data
        XCTAssertNil(persistedData)
    }

    func testRemoveSourceCookiesRetainsOtherOwnersWhileVisibilityIsGlobal() async throws {
        let persistence = FakeCookiePersistence()
        let store = PersistentHTTPCookieStore(persistence: persistence)
        let target = try url("https://example.invalid/")
        try await store.store([
            HTTPCookie(name: "a", value: "1", domain: "example.invalid")
        ], for: target, sourceIdentifier: "source-a")
        try await store.store([
            HTTPCookie(name: "b", value: "2", domain: "example.invalid")
        ], for: target, sourceIdentifier: "source-b")

        let globallyVisible = try await store.cookies(for: target, sourceIdentifier: "source-c")
        XCTAssertEqual(Set(globallyVisible.map(\.name)), ["a", "b"])
        try await store.removeAll(sourceIdentifier: "source-a")
        let remaining = try await store.cookies(for: target, sourceIdentifier: "source-c")
        XCTAssertEqual(remaining.map(\.name), ["b"])
    }

    func testConcurrentAccessPersistsEveryCookie() async throws {
        let persistence = FakeCookiePersistence()
        let store = PersistentHTTPCookieStore(persistence: persistence)
        let target = try url("https://example.invalid/")
        await withTaskGroup(of: Void.self) { group in
            for index in 0..<30 {
                group.addTask {
                    try? await store.store([
                        HTTPCookie(
                            name: "c\(index)", value: "\(index)", domain: "example.invalid"
                        )
                    ], for: target, sourceIdentifier: "source")
                }
            }
        }
        let restarted = PersistentHTTPCookieStore(persistence: persistence)
        let cookies = try await restarted.cookies(for: target, sourceIdentifier: nil)
        XCTAssertEqual(cookies.count, 30)
    }

    private func url(_ value: String) throws -> URL {
        try XCTUnwrap(URL(string: value))
    }
}

private actor FakeCookiePersistence: CookiePersistence {
    private(set) var data: Data?

    init(data: Data? = nil) {
        self.data = data
    }

    func load() -> Data? { data }
    func save(_ data: Data) { self.data = data }
    func remove() { data = nil }
}
