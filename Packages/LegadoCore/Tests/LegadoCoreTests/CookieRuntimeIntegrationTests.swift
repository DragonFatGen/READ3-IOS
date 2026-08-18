import Foundation
import XCTest
@testable import LegadoCore

final class CookieRuntimeIntegrationTests: XCTestCase {
    func testSearchBookInfoTOCAndContentShareOneAutomaticSession() async throws {
        let transport = RuntimeCookieTransport()
        let store = InMemoryHTTPCookieStore()
        let client = CookieSessionHTTPClient(transport: transport, cookieStore: store)
        let source = runtimeSource()

        let search = try await BookSourceSearchRuntime(httpClient: client)
            .search(source: source, keyword: "book")
        let book = try XCTUnwrap(search.first)
        let info = try await BookSourceBookInfoRuntime(httpClient: client)
            .fetchBookInfo(source: source, book: book)
        let chapters = try await BookSourceTOCRuntime(httpClient: client)
            .fetchTOC(source: source, book: info)
        _ = try await BookSourceContentRuntime(httpClient: client)
            .fetchContent(source: source, book: info, chapter: try XCTUnwrap(chapters.first))

        let cookies = await transport.requestCookies
        XCTAssertEqual(cookies["/search"], nil)
        XCTAssertEqual(cookies["/book"], "phase=search")
        XCTAssertEqual(cookies["/toc"], "phase=info")
        XCTAssertEqual(cookies["/content"], "phase=toc")
    }

    func testExploreCookieContinuesIntoBookDetailRuntime() async throws {
        let transport = RuntimeCookieTransport()
        let store = InMemoryHTTPCookieStore()
        let client = CookieSessionHTTPClient(transport: transport, cookieStore: store)
        let source = runtimeSource()

        let books = try await BookSourceExploreRuntime(httpClient: client)
            .explore(source: source, url: "/explore")
        _ = try await BookSourceBookInfoRuntime(httpClient: client)
            .fetchBookInfo(source: source, book: try XCTUnwrap(books.first))

        let cookies = await transport.requestCookies
        XCTAssertEqual(cookies["/explore"], nil)
        XCTAssertEqual(cookies["/book"], "phase=explore")
    }

    private func runtimeSource() -> BookSource {
        BookSource(
            bookSourceUrl: "https://example.invalid",
            bookSourceName: "Cookie fixture",
            exploreUrl: "列表::/explore",
            ruleExplore: ExploreRule(
                bookList: "class.book", name: "tag.a@text",
                author: "class.author@text", bookUrl: "tag.a@href"
            ),
            searchUrl: "https://example.invalid/search?q={{key}}",
            ruleSearch: SearchRule(
                bookList: "class.book", name: "tag.a@text",
                author: "class.author@text", bookUrl: "tag.a@href"
            ),
            ruleBookInfo: BookInfoRule(
                name: "tag.h1@text", author: "class.author@text",
                tocUrl: "class.toc@href", canReName: "1"
            ),
            ruleToc: TocRule(
                chapterList: "tag.li", chapterName: "tag.a@text", chapterUrl: "tag.a@href"
            ),
            ruleContent: ContentRule(content: "id.content@text")
        )
    }
}

private actor RuntimeCookieTransport: HTTPClient {
    private(set) var requestCookies: [String: String] = [:]

    func send(_ request: HTTPRequest) async throws -> HTTPResponse {
        let path = request.url.path
        if let cookie = request.headers["Cookie"] {
            requestCookies[path] = cookie
        }
        let body: String
        let cookieValue: String
        switch path {
        case "/search":
            body = bookListHTML
            cookieValue = "search"
        case "/explore":
            body = bookListHTML
            cookieValue = "explore"
        case "/book":
            body = #"<h1>Book</h1><span class="author">Author</span><a class="toc" href="/toc">TOC</a>"#
            cookieValue = "info"
        case "/toc":
            body = #"<ul><li><a href="/content">Chapter</a></li></ul>"#
            cookieValue = "toc"
        case "/content":
            body = #"<div id="content">Text</div>"#
            cookieValue = "content"
        default:
            body = ""
            cookieValue = "unknown"
        }
        return HTTPResponse(
            statusCode: 200,
            headers: HTTPHeaders(["Content-Type": "text/html; charset=utf-8"]),
            data: Data(body.utf8),
            finalURL: request.url,
            cookies: [HTTPCookie(
                name: "phase", value: cookieValue, domain: "example.invalid", isHostOnly: true
            )]
        )
    }

    private var bookListHTML: String {
        #"<div class="book"><a href="/book">Book</a><span class="author">Author</span></div>"#
    }
}
