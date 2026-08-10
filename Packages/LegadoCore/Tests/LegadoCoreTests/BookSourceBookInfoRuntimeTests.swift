import Foundation
import XCTest
@testable import LegadoCore

final class BookSourceBookInfoRuntimeTests: XCTestCase {
    func testHTMLBookInfoEndToEnd() async throws {
        let (runtime, _) = runtime(fixture: "html-basic.html")
        let result = try await runtime.fetchBookInfo(source: htmlSource(), book: book())
        XCTAssertEqual(result.name, "Book A")
        XCTAssertEqual(result.author, "AA")
        XCTAssertEqual(result.kind, "Fantasy")
        XCTAssertEqual(result.wordCount, "1.2万字")
        XCTAssertEqual(result.lastChapter, "Chapter 10")
        XCTAssertEqual(result.intro, "Intro A")
        XCTAssertEqual(result.coverURL, "https://example.invalid/covers/1.jpg")
        XCTAssertEqual(result.tocURL, "https://example.invalid/toc/1")
    }

    func testHTMLInitKeepsRelativeNodeContext() async throws {
        let (runtime, _) = runtime(fixture: "html-init-node.html")
        var source = htmlSource()
        source.ruleBookInfo = BookInfoRule(
            initialRule: "id.main-book", name: "tag.h1@text", author: "class.author@text",
            tocUrl: "tag.a@href", canReName: "true"
        )
        let result = try await runtime.fetchBookInfo(source: source, book: book())
        XCTAssertEqual(result.name, "Book A")
        XCTAssertEqual(result.author, "AA")
    }

    func testJSONInitKeepsObjectContext() async throws {
        let (runtime, _) = runtime(
            fixture: "json-init-node.json", contentType: "application/json",
            finalURL: "https://api.example.invalid/book/1"
        )
        let source = BookSource(
            bookSourceUrl: "https://api.example.invalid", bookSourceName: "JSON",
            ruleBookInfo: BookInfoRule(
                initialRule: "$.data.book", name: "$.name", author: "$.author",
                tocUrl: "$.toc", canReName: "true"
            )
        )
        let result = try await runtime.fetchBookInfo(source: source, book: book())
        XCTAssertEqual(result.name, "Book A")
        XCTAssertEqual(result.author, "AA")
        XCTAssertEqual(result.tocURL, "https://api.example.invalid/toc/1")
    }

    func testJSONWithoutInitUsesResponseRoot() async throws {
        let (runtime, _) = runtime(
            fixture: "json-basic.json", contentType: "application/json",
            finalURL: "https://api.example.invalid/book/1"
        )
        let source = BookSource(
            bookSourceUrl: "https://api.example.invalid", bookSourceName: "JSON",
            ruleBookInfo: BookInfoRule(
                name: "$.name", author: "$.author", tocUrl: "$.toc", canReName: "1"
            )
        )
        let result = try await runtime.fetchBookInfo(source: source, book: book())
        XCTAssertEqual(result.name, "Book A")
        XCTAssertEqual(result.author, "AA")
    }

    func testJSONMissingAuthorRetainsSearchAuthor() async throws {
        let (runtime, _) = runtime(
            fixture: "json-missing-field.json", contentType: "application/json"
        )
        let source = BookSource(
            bookSourceUrl: "https://example.invalid", bookSourceName: "JSON",
            ruleBookInfo: BookInfoRule(
                initialRule: "$.data.book", name: "$.name", author: "$.author",
                tocUrl: "$.toc", canReName: "1"
            )
        )
        let result = try await runtime.fetchBookInfo(source: source, book: book())
        XCTAssertEqual(result.author, "Search Author")
    }

    func testXPathInitKeepsRelativeElementContext() async throws {
        let (runtime, _) = runtime(fixture: "xpath-basic.html")
        let source = BookSource(
            bookSourceUrl: "https://example.invalid", bookSourceName: "XPath",
            ruleBookInfo: BookInfoRule(
                initialRule: "@XPath://article[@id='book']",
                name: "@XPath:.//h1/text()",
                author: "@XPath:.//span[@class='author']/text()",
                tocUrl: "@XPath:.//a[@class='toc']/@href", canReName: "true"
            )
        )
        let result = try await runtime.fetchBookInfo(source: source, book: book())
        XCTAssertEqual(result.name, "XPath Book")
        XCTAssertEqual(result.author, "XA")
        XCTAssertEqual(result.tocURL, "https://example.invalid/xpath/toc")
    }

    func testNilInitUsesWholeResponse() async throws {
        let (runtime, _) = runtime(fixture: "html-basic.html")
        let result = try await runtime.fetchBookInfo(source: htmlSource(initialRule: nil), book: book())
        XCTAssertEqual(result.name, "Book A")
    }

    func testEmptyInitUsesWholeResponse() async throws {
        let (runtime, _) = runtime(fixture: "html-basic.html")
        let result = try await runtime.fetchBookInfo(source: htmlSource(initialRule: "  "), book: book())
        XCTAssertEqual(result.author, "AA")
    }

    func testBlankTocFallsBackToCanonicalBookURL() async throws {
        let (runtime, _) = runtime(fixture: "empty.html")
        let source = BookSource(
            bookSourceUrl: "https://example.invalid", bookSourceName: "Empty",
            ruleBookInfo: BookInfoRule()
        )
        let result = try await runtime.fetchBookInfo(source: source, book: book())
        XCTAssertEqual(result.tocURL, "https://example.invalid/book/1")
    }

    func testRedirectURLResolvesCoverAndTocButDoesNotReplaceBookURL() async throws {
        let (runtime, _) = runtime(
            fixture: "html-relative-urls.html",
            finalURL: "https://mirror.example.invalid/books/1/"
        )
        var source = htmlSource()
        source.ruleBookInfo = BookInfoRule(
            initialRule: "id.book", coverUrl: "tag.img@src", tocUrl: "tag.a@href"
        )
        let result = try await runtime.fetchBookInfo(source: source, book: book())
        XCTAssertEqual(result.bookURL, "https://example.invalid/book/1")
        XCTAssertEqual(result.coverURL, "https://cdn.example.invalid/a.jpg")
        XCTAssertEqual(result.tocURL, "https://mirror.example.invalid/books/toc/1")
    }

    func testHTTP404BodyStillParses() async throws {
        let response = try response(fixture: "html-basic.html", statusCode: 404)
        let runtime = BookSourceBookInfoRuntime(httpClient: MockHTTPClient(response: response))
        let result = try await runtime.fetchBookInfo(source: htmlSource(), book: book())
        XCTAssertEqual(result.name, "Book A")
    }

    func testMalformedHTMLUsesParserRecovery() async throws {
        let (runtime, _) = runtime(fixture: "html-malformed.html")
        let result = try await runtime.fetchBookInfo(source: htmlSource(), book: book())
        XCTAssertTrue(result.name.contains("Recovered"))
    }

    func testMissingBookInfoRuleIsTyped() async throws {
        let runtime = BookSourceBookInfoRuntime(httpClient: MockHTTPClient(error: .invalidResponse))
        do {
            _ = try await runtime.fetchBookInfo(
                source: BookSource(bookSourceUrl: "https://example.invalid", bookSourceName: "None"),
                book: book()
            )
            XCTFail("Expected unsupported BookInfo")
        } catch {
            XCTAssertEqual(error as? BookInfoError, .bookInfoNotSupported)
        }
    }

    func testNetworkFailureIsTyped() async throws {
        let runtime = BookSourceBookInfoRuntime(httpClient: MockHTTPClient(error: .transportError("offline")))
        do {
            _ = try await runtime.fetchBookInfo(source: htmlSource(), book: book())
            XCTFail("Expected network failure")
        } catch let error as BookInfoError {
            guard case .networkFailed = error else { return XCTFail("Unexpected \(error)") }
        }
    }

    func testUnsupportedResponseCharsetIsTyped() async throws {
        let (runtime, _) = runtime(
            fixture: "html-basic.html", contentType: "text/html; charset=gbk"
        )
        do {
            _ = try await runtime.fetchBookInfo(source: htmlSource(), book: book())
            XCTFail("Expected decoding failure")
        } catch let error as BookInfoError {
            guard case .responseDecodeFailed = error else { return XCTFail("Unexpected \(error)") }
        }
    }

    func testRequestUsesRequestBuilderSourceAndOptionHeaders() async throws {
        let (runtime, client) = runtime(fixture: "html-basic.html")
        var source = htmlSource()
        source.header = #"{"User-Agent":"Source","X-Level":"source"}"#
        var input = book()
        input = BookSearchResult(
            name: input.name, author: input.author,
            bookURL: #"https://example.invalid/book/1,{"headers":{"X-Level":"detail"}}"#,
            sourceURL: input.sourceURL, sourceName: input.sourceName,
            sourceType: input.sourceType, sourceOrder: input.sourceOrder
        )
        _ = try await runtime.fetchBookInfo(source: source, book: input)
        let requests = await client.requests
        let request = try XCTUnwrap(requests.first)
        XCTAssertEqual(request.headers["User-Agent"], "Source")
        XCTAssertEqual(request.headers["X-Level"], "detail")
    }

    func testPOSTBookInfoUsesURLRequestOptions() async throws {
        let (runtime, client) = runtime(fixture: "html-basic.html")
        let input = BookSearchResult(
            name: "Search", author: "Search Author",
            bookURL: #"https://example.invalid/book/1,{"method":"POST","body":"id=1"}"#,
            sourceURL: "https://example.invalid", sourceName: "Source", sourceType: 0, sourceOrder: 0
        )
        _ = try await runtime.fetchBookInfo(source: htmlSource(), book: input)
        let requests = await client.requests
        let request = try XCTUnwrap(requests.first)
        XCTAssertEqual(request.method, .post)
        XCTAssertEqual(String(decoding: try XCTUnwrap(request.body), as: UTF8.self), "id=1")
    }

    func testNameAndAuthorRetainSearchValuesWithoutCanRenameRule() async throws {
        let (runtime, _) = runtime(fixture: "html-basic.html")
        var source = htmlSource()
        source.ruleBookInfo?.canReName = nil
        let result = try await runtime.fetchBookInfo(source: source, book: book())
        XCTAssertEqual(result.name, "Search Name")
        XCTAssertEqual(result.author, "Search Author")
    }

    func testOptionalFieldFailureRetainsSearchValue() async throws {
        let (runtime, _) = runtime(fixture: "html-basic.html")
        var source = htmlSource()
        source.ruleBookInfo?.intro = "@XPath:("
        let result = try await runtime.fetchBookInfo(source: source, book: book(intro: "Search intro"))
        XCTAssertEqual(result.intro, "Search intro")
    }

    func testPutAndGetShareContextAcrossFields() async throws {
        let (runtime, _) = runtime(fixture: "html-basic.html")
        var source = htmlSource()
        source.ruleBookInfo?.name = #"tag.h1@text@put:{"saved":"class.author@text"}"#
        source.ruleBookInfo?.author = "@get:{saved}"
        let result = try await runtime.fetchBookInfo(source: source, book: book())
        XCTAssertEqual(result.name, "Book A")
        XCTAssertEqual(result.author, "AA")
    }

    func testInitPutIsVisibleToLaterField() async throws {
        let (runtime, _) = runtime(fixture: "html-basic.html")
        var source = htmlSource()
        source.ruleBookInfo = BookInfoRule(
            initialRule: #"id.book@put:{"saved":"class.author@text"}"#,
            name: "@get:{saved}", tocUrl: "tag.a@href", canReName: "1"
        )
        let result = try await runtime.fetchBookInfo(source: source, book: book())
        XCTAssertEqual(result.name, "AA")
    }

    func testEachFieldRestartsResultFromInitNode() async throws {
        let (runtime, _) = runtime(fixture: "html-basic.html")
        var source = htmlSource()
        source.ruleBookInfo?.name = "tag.h1@text"
        source.ruleBookInfo?.author = "class.author@text"
        let result = try await runtime.fetchBookInfo(source: source, book: book())
        XCTAssertEqual(result.author, "AA")
    }

    func testStructuredNodeDirectJavaScriptIsExplicitlyUnsupported() async throws {
        let (runtime, _) = runtime(fixture: "html-basic.html")
        var source = htmlSource()
        source.ruleBookInfo?.name = "@js:result"
        do {
            _ = try await runtime.fetchBookInfo(source: source, book: book())
            XCTFail("Expected structured input failure")
        } catch let error as BookInfoError {
            guard case .fieldRuleFailed(field: "name", message: _) = error else {
                return XCTFail("Unexpected \(error)")
            }
        }
    }

    func testInitFailureIsTyped() async throws {
        let (runtime, _) = runtime(fixture: "html-basic.html")
        var source = htmlSource(initialRule: "id.missing")
        do {
            _ = try await runtime.fetchBookInfo(source: source, book: book())
            XCTFail("Expected init failure")
        } catch let error as BookInfoError {
            guard case .initRuleFailed = error else { return XCTFail("Unexpected \(error)") }
        }
    }

    func testProductionJavaNetworkRuleRemainsUnsupported() async throws {
        let (runtime, _) = runtime(fixture: "html-basic.html")
        var source = htmlSource()
        source.ruleBookInfo?.name = "@js:java.ajax('https://example.invalid')"
        do {
            _ = try await runtime.fetchBookInfo(source: source, book: book())
            XCTFail("Expected capability error")
        } catch {
            XCTAssertEqual(error as? BookInfoError, .unsupportedJavaScriptNetworkHost)
        }
    }

    func testConcurrentBookInfoCallsRemainIsolated() async throws {
        let responseA = try response(fixture: "html-init-node.html", finalURL: "https://a.invalid/book/1")
        let responseB = try response(fixture: "xpath-basic.html", finalURL: "https://b.invalid/book/2")
        let runtimeA = BookSourceBookInfoRuntime(httpClient: MockHTTPClient(response: responseA))
        let runtimeB = BookSourceBookInfoRuntime(httpClient: MockHTTPClient(response: responseB))
        var sourceA = htmlSource()
        sourceA.ruleBookInfo = BookInfoRule(initialRule: "id.main-book", name: "tag.h1@text", tocUrl: "tag.a@href", canReName: "1")
        let sourceB = BookSource(
            bookSourceUrl: "https://b.invalid", bookSourceName: "B",
            ruleBookInfo: BookInfoRule(initialRule: "id.other", name: "tag.h1@text", canReName: "1")
        )
        async let a = runtimeA.fetchBookInfo(source: sourceA, book: book(url: "https://a.invalid/book/1"))
        async let b = runtimeB.fetchBookInfo(source: sourceB, book: book(url: "https://b.invalid/book/2"))
        let (valueA, valueB) = try await (a, b)
        let values = [valueA, valueB]
        XCTAssertEqual(Set(values.map(\.name)), Set(["Book A", "Other"]))
        XCTAssertEqual(Set(values.map(\.bookURL)), Set(["https://a.invalid/book/1", "https://b.invalid/book/2"]))
    }

    func testSearchThenBookInfoMockIntegration() async throws {
        let searchResponse = HTTPResponse(
            statusCode: 200, data: try FixtureLoader.data(named: "html-basic.html", directory: "search"),
            finalURL: try XCTUnwrap(URL(string: "https://example.invalid/search"))
        )
        let infoResponse = try response(fixture: "html-basic.html")
        let client = MockHTTPClient(results: [.success(searchResponse), .success(infoResponse)])
        let searchRuntime = BookSourceSearchRuntime(httpClient: client)
        let infoRuntime = BookSourceBookInfoRuntime(httpClient: client)
        var source = htmlSource()
        source.searchUrl = "https://example.invalid/search"
        source.ruleSearch = SearchRule(
            bookList: "class.book", name: "tag.h2@text", author: "class.author@text",
            bookUrl: "tag.a@href"
        )
        let searchResults = try await searchRuntime.search(source: source, keyword: "A")
        let selected = try XCTUnwrap(searchResults.first)
        let detail = try await infoRuntime.fetchBookInfo(source: source, book: selected)
        XCTAssertEqual(detail.name, "Book A")
        XCTAssertEqual(detail.tocURL, "https://example.invalid/toc/1")
    }

    private func runtime(
        fixture: String,
        contentType: String = "text/html; charset=utf-8",
        finalURL: String = "https://example.invalid/book/1"
    ) -> (BookSourceBookInfoRuntime, MockHTTPClient) {
        let response = try! self.response(fixture: fixture, contentType: contentType, finalURL: finalURL)
        let client = MockHTTPClient(response: response)
        return (BookSourceBookInfoRuntime(httpClient: client), client)
    }

    private func response(
        fixture: String,
        contentType: String = "text/html; charset=utf-8",
        finalURL: String = "https://example.invalid/book/1",
        statusCode: Int = 200
    ) throws -> HTTPResponse {
        HTTPResponse(
            statusCode: statusCode,
            headers: HTTPHeaders(["Content-Type": contentType]),
            data: try FixtureLoader.data(named: fixture, directory: "book-info"),
            finalURL: try XCTUnwrap(URL(string: finalURL))
        )
    }

    private func htmlSource(initialRule: String? = "id.book") -> BookSource {
        BookSource(
            bookSourceUrl: "https://example.invalid", bookSourceName: "Source", customOrder: 7,
            ruleBookInfo: BookInfoRule(
                initialRule: initialRule, name: "tag.h1@text", author: "class.author@text",
                intro: "class.intro@text", kind: "class.kind@text",
                lastChapter: "class.latest@text", coverUrl: "tag.img@src",
                tocUrl: "tag.a@href", wordCount: "class.words@text", canReName: "true"
            )
        )
    }

    private func book(
        url: String = "https://example.invalid/book/1",
        intro: String? = nil
    ) -> BookSearchResult {
        BookSearchResult(
            name: "Search Name", author: "Search Author", bookURL: url, intro: intro,
            sourceURL: "https://example.invalid", sourceName: "Source",
            sourceType: 0, sourceOrder: 7
        )
    }
}
