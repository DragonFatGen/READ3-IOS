import Foundation
import XCTest
@testable import LegadoCore

final class BookSourceSearchRuntimeTests: XCTestCase {
    func testHTMLSearchEndToEnd() async throws {
        let (runtime, _) = runtime(fixture: "html-basic.html")
        let result = try await runtime.search(source: htmlSource(), keyword: "swift", page: 2)
        XCTAssertEqual(result, [BookSearchResult(
            name: "Book A", author: "Author A", bookURL: "https://example.invalid/book/a",
            coverURL: "https://example.invalid/a.jpg", intro: "Intro A", kind: "Fantasy",
            wordCount: "1.2万字", lastChapter: "Chapter 10", sourceURL: "https://example.invalid",
            sourceName: "HTML", sourceType: 0, sourceOrder: 7
        )])
    }

    func testHTMLMultipleItemsDoNotCrossContaminate() async throws {
        let (runtime, _) = runtime(fixture: "html-multiple.html")
        let result = try await runtime.search(source: basicHTMLSource(), keyword: "x")
        XCTAssertEqual(result.map(\.name), ["A", "B"])
        XCTAssertEqual(result.map(\.author), ["AA", "BB"])
    }

    func testJSONSearchEndToEnd() async throws {
        let (runtime, _) = runtime(
            fixture: "json-multiple.json",
            contentType: "application/json; charset=utf-8",
            finalURL: "https://api.example.invalid/search/result"
        )
        let result = try await runtime.search(source: jsonSource(), keyword: "json")
        XCTAssertEqual(result.map(\.name), ["A", "B"])
        XCTAssertEqual(result.map(\.bookURL), ["https://api.example.invalid/a", "https://api.example.invalid/b"])
    }

    func testXPathSearchEndToEnd() async throws {
        let (runtime, _) = runtime(fixture: "xpath-basic.html")
        let source = BookSource(
            bookSourceUrl: "https://example.invalid", bookSourceName: "XPath",
            searchUrl: "https://example.invalid/search",
            ruleSearch: SearchRule(
                bookList: "@XPath://article", name: "@XPath:.//h2/text()",
                author: "@XPath:.//span[@class='author']/text()",
                bookUrl: "@XPath:.//a/@href"
            )
        )
        let result = try await runtime.search(source: source, keyword: "x")
        XCTAssertEqual(result.map(\.name), ["XPath A", "XPath B"])
        XCTAssertEqual(result.map(\.author), ["XA", "XB"])
    }

    func testSearchRequestContainsKeywordAndPage() async throws {
        let (runtime, client) = runtime(fixture: "empty.html")
        _ = try await runtime.search(source: basicHTMLSource(), keyword: "hello world", page: 3)
        let requests = await client.requests
        let request = try XCTUnwrap(requests.first)
        XCTAssertEqual(request.url.absoluteString, "https://example.invalid/search?q=hello+world&page=3")
    }

    func testPOSTSearchUsesRequestBuilderBodyAndHeaders() async throws {
        let (runtime, client) = runtime(fixture: "html-multiple.html")
        var source = basicHTMLSource()
        source.searchUrl = #"https://example.invalid/search,{"method":"POST","body":"q={{key}}&page={{page}}","headers":{"X-Mode":"post"}}"#
        _ = try await runtime.search(source: source, keyword: "books", page: 2)
        let requests = await client.requests
        let request = try XCTUnwrap(requests.first)
        XCTAssertEqual(request.method, .post)
        XCTAssertEqual(String(decoding: try XCTUnwrap(request.body), as: UTF8.self), "q=books&page=2")
        XCTAssertEqual(request.headers["X-Mode"], "post")
        XCTAssertEqual(request.headers["Content-Type"], "application/x-www-form-urlencoded")
    }

    func testSourceAndOptionHeaderPriorityRemainInRequestBuilder() async throws {
        let (runtime, client) = runtime(fixture: "empty.html")
        var source = basicHTMLSource()
        source.header = #"{"User-Agent":"Source","X-Level":"source"}"#
        source.searchUrl = #"https://example.invalid/search,{"headers":{"X-Level":"option"}}"#
        _ = try await runtime.search(source: source, keyword: "x")
        let requests = await client.requests
        let request = try XCTUnwrap(requests.first)
        XCTAssertEqual(request.headers["User-Agent"], "Source")
        XCTAssertEqual(request.headers["X-Level"], "option")
    }

    func testPageAlternativeIsDelegatedToRequestBuilder() async throws {
        let (runtime, client) = runtime(fixture: "empty.html")
        var source = basicHTMLSource()
        source.searchUrl = "https://example.invalid/<first,second,last>"
        _ = try await runtime.search(source: source, keyword: "x", page: 2)
        let requests = await client.requests
        XCTAssertEqual(try XCTUnwrap(requests.first).url.absoluteString, "https://example.invalid/second")
    }

    func testRedirectFinalURLResolvesRelativeBookAndCoverURLs() async throws {
        let response = try response(
            fixture: "html-relative-url.html",
            finalURL: "https://mirror.example.invalid/search/result"
        )
        let runtime = BookSourceSearchRuntime(httpClient: MockHTTPClient(response: response))
        let results = try await runtime.search(source: basicHTMLSource(), keyword: "x")
        let result = try XCTUnwrap(results.first)
        XCTAssertEqual(result.bookURL, "https://mirror.example.invalid/book/1")
        XCTAssertEqual(result.coverURL, "https://cdn.example.invalid/cover.jpg")
    }

    func testEmptyBookListReturnsEmptyArray() async throws {
        let (runtime, _) = runtime(fixture: "empty.html")
        let result = try await runtime.search(source: basicHTMLSource(), keyword: "x")
        XCTAssertEqual(result, [])
    }

    func testMissingNameFiltersOnlyThatJSONItem() async throws {
        let (runtime, _) = runtime(
            fixture: "json-missing-field.json",
            contentType: "application/json",
            finalURL: "https://api.example.invalid/search/result"
        )
        let result = try await runtime.search(source: jsonSource(), keyword: "x")
        XCTAssertEqual(result.map(\.name), ["Present"])
    }

    func testEmptyBookURLFallsBackToResponseBaseURL() async throws {
        let (runtime, _) = runtime(fixture: "html-basic.html")
        var source = htmlSource()
        source.ruleSearch?.bookUrl = nil
        let results = try await runtime.search(source: source, keyword: "x")
        let result = try XCTUnwrap(results.first)
        XCTAssertEqual(result.bookURL, "https://example.invalid/search/result")
    }

    func testPutGetCanCrossFieldsWithinOneItemWithoutCrossingItems() async throws {
        let (runtime, _) = runtime(fixture: "html-multiple.html")
        var source = basicHTMLSource()
        source.ruleSearch?.name = #"tag.h2@text@put:{"saved":"class.author@text"}"#
        source.ruleSearch?.author = "@get:{saved}"
        let result = try await runtime.search(source: source, keyword: "x")
        XCTAssertEqual(result.map(\.author), ["AA", "BB"])
    }

    func testPureJavaScriptFieldUsesInjectedExecutorAfterScalarSelector() async throws {
        let (baseRuntime, client) = runtime(fixture: "html-basic.html")
        _ = baseRuntime
        var source = htmlSource()
        source.ruleSearch?.name = "tag.h2@text<js>result + '!'</js>"
        let runtime = BookSourceSearchRuntime(httpClient: client, javaScriptExecutor: SearchFakeJavaScriptExecutor())
        let results = try await runtime.search(source: source, keyword: "x")
        let result = try XCTUnwrap(results.first)
        XCTAssertEqual(result.name, "Book A!")
    }

    func testProductionJavaScriptNetworkHostRemainsExplicitlyUnsupported() async throws {
        let (runtime, _) = runtime(fixture: "html-basic.html")
        var source = htmlSource()
        source.ruleSearch?.intro = "@js:java.ajax('/more')"
        do {
            _ = try await runtime.search(source: source, keyword: "x")
            XCTFail("Expected capability error")
        } catch {
            XCTAssertEqual(error as? BookSearchError, .unsupportedJavaScriptNetworkHost)
        }
    }

    func testConcurrentSearchesRemainIsolated() async throws {
        let (firstRuntime, _) = runtime(fixture: "html-multiple.html")
        let (secondRuntime, _) = runtime(
            fixture: "json-multiple.json",
            contentType: "application/json",
            finalURL: "https://api.example.invalid/search/result"
        )
        async let first = firstRuntime.search(source: basicHTMLSource(), keyword: "html")
        async let second = secondRuntime.search(source: jsonSource(), keyword: "json")
        let values = try await (first, second)
        XCTAssertEqual(values.0.map(\.name), ["A", "B"])
        XCTAssertEqual(values.1.map(\.author), ["AA", "BB"])
    }

    func testSelectorThenRegexFieldComposition() async throws {
        let (runtime, _) = runtime(fixture: "html-basic.html")
        var source = basicHTMLSource()
        source.ruleSearch?.name = "tag.h2@text##Book ##Novel "
        let result = try await runtime.search(source: source, keyword: "x")
        XCTAssertEqual(result.first?.name, "Novel A")
    }

    func testSelectorInsideTemplateFieldComposition() async throws {
        let (runtime, _) = runtime(fixture: "html-basic.html")
        var source = basicHTMLSource()
        source.ruleSearch?.name = "{{@CSS:h2@text}} Edition"
        let result = try await runtime.search(source: source, keyword: "x")
        XCTAssertEqual(result.first?.name, "Book A Edition")
    }

    func testReverseBookListPrefix() async throws {
        let (runtime, _) = runtime(fixture: "html-multiple.html")
        var source = basicHTMLSource()
        source.ruleSearch?.bookList = "-class.book"
        let result = try await runtime.search(source: source, keyword: "x")
        XCTAssertEqual(result.map(\.name), ["B", "A"])
    }

    func testHTTP404BodyStillParsesLikeAndroid() async throws {
        let body = try FixtureLoader.data(named: "html-basic.html", directory: "search")
        let response = HTTPResponse(
            statusCode: 404,
            headers: HTTPHeaders(["Content-Type": "text/html"]),
            data: body,
            finalURL: try XCTUnwrap(URL(string: "https://example.invalid/search"))
        )
        let runtime = BookSourceSearchRuntime(httpClient: MockHTTPClient(response: response))
        let result = try await runtime.search(source: basicHTMLSource(), keyword: "x")
        XCTAssertEqual(result.first?.name, "Book A")
    }

    func testUnsupportedResponseCharsetIsTypedSearchError() async throws {
        let (runtime, _) = runtime(fixture: "html-basic.html", contentType: "text/html; charset=gbk")
        do {
            _ = try await runtime.search(source: basicHTMLSource(), keyword: "x")
            XCTFail("Expected decode error")
        } catch let error as BookSearchError {
            guard case .responseDecodeFailed = error else { return XCTFail("Unexpected \(error)") }
        }
    }

    func testTransportFailureIsTypedSearchError() async throws {
        let runtime = BookSourceSearchRuntime(
            httpClient: MockHTTPClient(error: .transportError("offline"))
        )
        do {
            _ = try await runtime.search(source: basicHTMLSource(), keyword: "x")
            XCTFail("Expected network error")
        } catch let error as BookSearchError {
            guard case .networkFailed = error else { return XCTFail("Unexpected \(error)") }
        }
    }

    func testMalformedHTMLRemainsRecoverable() async throws {
        let (runtime, _) = runtime(fixture: "malformed.html")
        let result = try await runtime.search(source: basicHTMLSource(), keyword: "x")
        XCTAssertEqual(result.first?.name, "Recoverable Writer")
    }

    func testURLResolverCoversRelativeForms() {
        let resolver = URLResolver()
        let base = "https://example.invalid/a/b/page"
        XCTAssertEqual(resolver.resolve("/book/1", against: base), "https://example.invalid/book/1")
        XCTAssertEqual(resolver.resolve("book/1", against: base), "https://example.invalid/a/b/book/1")
        XCTAssertEqual(resolver.resolve("../book/1", against: base), "https://example.invalid/a/book/1")
        XCTAssertEqual(resolver.resolve("?x=1", against: base), "https://example.invalid/a/b/page?x=1")
        XCTAssertEqual(resolver.resolve("#chapter", against: base), "https://example.invalid/a/b/page#chapter")
    }

    private func runtime(
        fixture: String,
        contentType: String = "text/html; charset=utf-8",
        finalURL: String = "https://example.invalid/search/result"
    ) -> (BookSourceSearchRuntime, MockHTTPClient) {
        let response = try! self.response(fixture: fixture, contentType: contentType, finalURL: finalURL)
        let client = MockHTTPClient(response: response)
        return (BookSourceSearchRuntime(httpClient: client), client)
    }

    private func response(
        fixture: String,
        contentType: String = "text/html; charset=utf-8",
        finalURL: String = "https://example.invalid/search/result"
    ) throws -> HTTPResponse {
        HTTPResponse(
            statusCode: 200,
            headers: HTTPHeaders(["Content-Type": contentType]),
            data: try FixtureLoader.data(named: fixture, directory: "search"),
            finalURL: try XCTUnwrap(URL(string: finalURL))
        )
    }

    private func basicHTMLSource() -> BookSource {
        BookSource(
            bookSourceUrl: "https://example.invalid", bookSourceName: "HTML", customOrder: 7,
            searchUrl: "https://example.invalid/search?q={{key}}&page={{page}}",
            ruleSearch: SearchRule(
                bookList: "class.book", name: "tag.h2@text", author: "class.author@text",
                bookUrl: "tag.a@href", coverUrl: "tag.img@src"
            )
        )
    }

    private func htmlSource() -> BookSource {
        var source = basicHTMLSource()
        source.ruleSearch?.intro = "class.intro@text"
        source.ruleSearch?.kind = "class.kind@text"
        source.ruleSearch?.wordCount = "class.words@text"
        source.ruleSearch?.lastChapter = "class.last@text"
        return source
    }

    private func jsonSource() -> BookSource {
        BookSource(
            bookSourceUrl: "https://api.example.invalid", bookSourceName: "JSON",
            searchUrl: "https://api.example.invalid/search?q={{key}}",
            ruleSearch: SearchRule(
                bookList: "$.items[*]", name: "$.name", author: "$.author", bookUrl: "$.url"
            )
        )
    }
}

private struct SearchFakeJavaScriptExecutor: RuleJavaScriptExecutor {
    func execute(script: String, context: JavaScriptExecutionContext) throws -> JavaScriptExecutionResult {
        .string(context.result.stringValue + "!")
    }
}
