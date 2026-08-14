import Foundation
import XCTest
@testable import LegadoCore

final class BookSourceBookInfoRuntimeTests: XCTestCase {
    func testHTMLBookInfoEndToEnd() async throws {
        let (runtime, _) = runtime(fixture: "html-basic.html")
        let result = try await runtime.fetchBookInfo(source: htmlSource(), book: book())
        XCTAssertEqual(result.name, "Book A")
        XCTAssertEqual(result.author, "Author A")
        XCTAssertEqual(result.kind, "Fantasy")
        XCTAssertEqual(result.wordCount, "1.2万字")
        XCTAssertEqual(result.lastChapter, "Chapter 10")
        XCTAssertEqual(result.intro, "Intro A")
        XCTAssertEqual(result.coverURL, "https://example.invalid/covers/a.jpg")
        XCTAssertEqual(result.tocURL, "https://example.invalid/toc/a")
    }

    func testHTMLInitKeepsFieldsRelativeToSelectedNode() async throws {
        let (runtime, _) = runtime(fixture: "html-init-node.html")
        var source = minimalHTMLSource()
        source.ruleBookInfo?.`init` = "id.main-book"
        let result = try await runtime.fetchBookInfo(source: source, book: book())
        XCTAssertEqual(result.name, "Book A")
        XCTAssertEqual(result.author, "AA")
        XCTAssertEqual(result.tocURL, "https://example.invalid/toc/1")
    }

    func testJSONInitKeepsObjectWithoutStringRoundTrip() async throws {
        let (runtime, _) = runtime(
            fixture: "json-init-node.json", contentType: "application/json"
        )
        let result = try await runtime.fetchBookInfo(source: jsonSource(), book: book())
        XCTAssertEqual(result.name, "Book A")
        XCTAssertEqual(result.author, "AA")
        XCTAssertEqual(result.tocURL, "https://example.invalid/toc/1")
    }

    func testXPathInitKeepsRelativeElementContext() async throws {
        let (runtime, _) = runtime(fixture: "xpath-basic.html")
        let source = BookSource(
            bookSourceUrl: "https://example.invalid", bookSourceName: "XPath",
            ruleBookInfo: BookInfoRule(
                initialRule: "@XPath://article[@id='book']",
                name: "@XPath:.//h1/text()",
                author: "@XPath:.//span[@class='author']/text()",
                tocUrl: "@XPath:.//a[@class='toc']/@href",
                canReName: "1"
            )
        )
        let result = try await runtime.fetchBookInfo(source: source, book: book())
        XCTAssertEqual(result.name, "XPath Book")
        XCTAssertEqual(result.author, "XPath Author")
        XCTAssertEqual(result.tocURL, "https://example.invalid/xpath/toc")
    }

    func testNoInitUsesWholeResponseRoot() async throws {
        let (runtime, _) = runtime(fixture: "html-basic.html")
        var source = minimalHTMLSource()
        source.ruleBookInfo?.`init` = nil
        let result = try await runtime.fetchBookInfo(source: source, book: book())
        XCTAssertEqual(result.name, "Book A")
    }

    func testEmptyInitUsesWholeResponseRoot() async throws {
        let (runtime, _) = runtime(fixture: "html-basic.html")
        var source = minimalHTMLSource()
        source.ruleBookInfo?.`init` = "  \n "
        let result = try await runtime.fetchBookInfo(source: source, book: book())
        XCTAssertEqual(result.author, "Author A")
    }

    func testInitPutIsVisibleToName() async throws {
        let (runtime, _) = runtime(fixture: "html-init-node.html")
        var source = minimalHTMLSource()
        source.ruleBookInfo?.`init` = #"id.main-book@put:{"saved":"id.main-book@tag.h1@text"}"#
        source.ruleBookInfo?.name = "@get:{saved}"
        let result = try await runtime.fetchBookInfo(source: source, book: book())
        XCTAssertEqual(result.name, "Book A")
    }

    func testNamePutIsVisibleToAuthorInAndroidFieldOrder() async throws {
        let (runtime, _) = runtime(fixture: "html-basic.html")
        var source = minimalHTMLSource()
        source.ruleBookInfo?.name = #"tag.h1@text@put:{"saved":"class.author@text"}"#
        source.ruleBookInfo?.author = "@get:{saved}"
        let result = try await runtime.fetchBookInfo(source: source, book: book())
        XCTAssertEqual(result.author, "Author A")
    }

    func testPreviousFieldResultIsNotNextFieldInput() async throws {
        let (runtime, _) = runtime(fixture: "html-basic.html")
        var source = minimalHTMLSource()
        source.ruleBookInfo?.name = "tag.h1@text"
        source.ruleBookInfo?.author = "class.author@text"
        let result = try await runtime.fetchBookInfo(source: source, book: book())
        XCTAssertEqual(result.author, "Author A")
    }

    func testRenameDisabledRetainsSearchNameAndAuthor() async throws {
        let (runtime, _) = runtime(fixture: "html-basic.html")
        var source = minimalHTMLSource()
        source.ruleBookInfo?.canReName = nil
        let result = try await runtime.fetchBookInfo(
            source: source, book: book(name: "Search Name", author: "Search Author")
        )
        XCTAssertEqual(result.name, "Search Name")
        XCTAssertEqual(result.author, "Search Author")
    }

    func testEmptyNameAndAuthorRetainSearchValues() async throws {
        let (runtime, _) = runtime(fixture: "json-missing-field.json", contentType: "application/json")
        var source = jsonSource()
        source.ruleBookInfo?.author = "$.missing"
        let result = try await runtime.fetchBookInfo(
            source: source, book: book(name: "Search", author: "Existing")
        )
        XCTAssertEqual(result.author, "Existing")
    }

    func testEmptyTocFallsBackToCanonicalBookURL() async throws {
        let (runtime, _) = runtime(fixture: "empty.html")
        let source = BookSource(
            bookSourceUrl: "https://example.invalid", bookSourceName: "Empty",
            ruleBookInfo: BookInfoRule()
        )
        let result = try await runtime.fetchBookInfo(source: source, book: book())
        XCTAssertEqual(result.tocURL, "https://example.invalid/book/1")
    }

    func testRedirectFinalURLResolvesCoverAndTocButNotBookURL() async throws {
        let (runtime, _) = runtime(
            fixture: "html-relative-urls.html",
            finalURL: "https://mirror.example.invalid/books/1/"
        )
        var source = minimalHTMLSource()
        source.ruleBookInfo?.`init` = "id.book"
        source.ruleBookInfo?.coverUrl = "tag.img@src"
        let result = try await runtime.fetchBookInfo(source: source, book: book())
        XCTAssertEqual(result.bookURL, "https://example.invalid/book/1")
        XCTAssertEqual(result.coverURL, "https://cdn.example.invalid/a.jpg")
        XCTAssertEqual(result.tocURL, "https://mirror.example.invalid/books/toc/1")
    }

    func testRelativeTocFormsUseSharedURLResolver() async throws {
        let forms = [
            ("/toc/1", "https://mirror.example.invalid/toc/1"),
            ("toc/1", "https://mirror.example.invalid/books/1/toc/1"),
            ("../toc/1", "https://mirror.example.invalid/books/toc/1"),
            ("//cdn.example.invalid/toc", "https://cdn.example.invalid/toc"),
            ("https://other.invalid/toc", "https://other.invalid/toc"),
            ("?chapter=1", "https://mirror.example.invalid/books/1/?chapter=1"),
            ("#anchor", "https://mirror.example.invalid/books/1/#anchor")
        ]
        for (raw, expected) in forms {
            let response = HTTPResponse(
                statusCode: 200, data: Data("<html></html>".utf8),
                finalURL: try XCTUnwrap(URL(string: "https://mirror.example.invalid/books/1/"))
            )
            let runtime = BookSourceBookInfoRuntime(
                httpClient: MockHTTPClient(response: response),
                javaScriptExecutor: LiteralJavaScriptExecutor(value: raw)
            )
            var source = minimalHTMLSource()
            source.ruleBookInfo?.tocUrl = "@js:'literal'"
            let result = try await runtime.fetchBookInfo(source: source, book: book())
            XCTAssertEqual(result.tocURL, expected)
        }
    }

    func testPOSTBookInfoUsesRequestBuilderOptionsAndHeaders() async throws {
        let (runtime, client) = runtime(fixture: "html-basic.html")
        let optionBook = book(url: #"https://example.invalid/info,{"method":"POST","body":"id=1","headers":{"X-Info":"yes"}}"#)
        _ = try await runtime.fetchBookInfo(source: htmlSource(), book: optionBook)
        let requests = await client.requests
        let request = try XCTUnwrap(requests.first)
        XCTAssertEqual(request.method, .post)
        XCTAssertEqual(String(decoding: try XCTUnwrap(request.body), as: UTF8.self), "id=1")
        XCTAssertEqual(request.headers["X-Info"], "yes")
    }

    func testSourceHeaderAndCookieRemainRequestBuilderResponsibilities() async throws {
        let cookieStore = InMemoryHTTPCookieStore()
        await cookieStore.store([
            HTTPCookie(name: "session", value: "abc", domain: "example.invalid")
        ], for: try XCTUnwrap(URL(string: "https://example.invalid")), sourceIdentifier: "https://example.invalid")
        let response = try response(fixture: "html-basic.html")
        let client = MockHTTPClient(response: response)
        let runtime = BookSourceBookInfoRuntime(
            httpClient: client, requestBuilder: RequestBuilder(cookieStore: cookieStore)
        )
        var source = htmlSource()
        source.header = #"{"X-Source":"book"}"#
        _ = try await runtime.fetchBookInfo(source: source, book: book())
        let requests = await client.requests
        let request = try XCTUnwrap(requests.first)
        XCTAssertEqual(request.headers["X-Source"], "book")
        XCTAssertEqual(request.headers["Cookie"], "session=abc")
    }

    func testHTTP404BodyStillParses() async throws {
        let response = HTTPResponse(
            statusCode: 404,
            data: try FixtureLoader.data(named: "html-basic.html", directory: "book-info"),
            finalURL: try XCTUnwrap(URL(string: "https://example.invalid/book/1"))
        )
        let runtime = BookSourceBookInfoRuntime(httpClient: MockHTTPClient(response: response))
        let result = try await runtime.fetchBookInfo(source: htmlSource(), book: book())
        XCTAssertEqual(result.name, "Book A")
    }

    func testUnsupportedCharsetIsTypedDecodeError() async throws {
        let (runtime, _) = runtime(
            fixture: "html-basic.html",
            contentType: "text/html; charset=x-unsupported-test"
        )
        await XCTAssertThrowsErrorAsync(try await runtime.fetchBookInfo(source: htmlSource(), book: book())) {
            guard let error = $0 as? BookInfoError,
                  case .responseDecodeFailed = error else {
                return XCTFail("Unexpected \($0)")
            }
        }
    }

    func testTransportFailureIsTypedNetworkError() async throws {
        let runtime = BookSourceBookInfoRuntime(
            httpClient: MockHTTPClient(error: .transportError("offline"))
        )
        await XCTAssertThrowsErrorAsync(try await runtime.fetchBookInfo(source: htmlSource(), book: book())) {
            guard let error = $0 as? BookInfoError,
                  case .networkFailed = error else {
                return XCTFail("Unexpected \($0)")
            }
        }
    }

    func testInvalidInitAbortsWithInitError() async throws {
        let (runtime, _) = runtime(fixture: "json-basic.json", contentType: "application/json")
        var source = jsonSource()
        source.ruleBookInfo?.`init` = "$.missing"
        await XCTAssertThrowsErrorAsync(try await runtime.fetchBookInfo(source: source, book: book())) {
            guard let error = $0 as? BookInfoError,
                  case .initRuleFailed = error else {
                return XCTFail("Unexpected \($0)")
            }
        }
    }

    func testRequiredNameRuleErrorAborts() async throws {
        let (runtime, _) = runtime(fixture: "html-basic.html")
        var source = htmlSource()
        source.ruleBookInfo?.name = "@XPath:["
        await XCTAssertThrowsErrorAsync(try await runtime.fetchBookInfo(source: source, book: book())) {
            guard let error = $0 as? BookInfoError,
                  case let .fieldRuleFailed(field, _) = error else {
                return XCTFail("Unexpected \($0)")
            }
            XCTAssertEqual(field, "name")
        }
    }

    func testOptionalFieldErrorRetainsSearchValue() async throws {
        let (runtime, _) = runtime(fixture: "html-basic.html")
        var source = htmlSource()
        source.ruleBookInfo?.kind = "@XPath:["
        let result = try await runtime.fetchBookInfo(source: source, book: book(kind: "Search Kind"))
        XCTAssertEqual(result.kind, "Search Kind")
    }

    func testPureJavaScriptAfterScalarSelectorUsesInjectedExecutor() async throws {
        let response = try response(fixture: "html-basic.html")
        let runtime = BookSourceBookInfoRuntime(
            httpClient: MockHTTPClient(response: response),
            javaScriptExecutor: SuffixJavaScriptExecutor()
        )
        var source = htmlSource()
        source.ruleBookInfo?.name = "tag.h1@text<js>result + '!'</js>"
        let result = try await runtime.fetchBookInfo(source: source, book: book())
        XCTAssertEqual(result.name, "Book A!")
    }

    func testPureJavaScriptInitReceivesResponseString() async throws {
        let response = try response(fixture: "html-basic.html")
        let runtime = BookSourceBookInfoRuntime(
            httpClient: MockHTTPClient(response: response),
            javaScriptExecutor: IdentityJavaScriptExecutor()
        )
        var source = htmlSource()
        source.ruleBookInfo?.`init` = "@js:result"
        let result = try await runtime.fetchBookInfo(source: source, book: book())
        XCTAssertEqual(result.name, "Book A")
    }

    func testStructuredInitDirectJavaScriptIsExplicitlyUnsupported() async throws {
        let (base, client) = runtime(fixture: "html-init-node.html")
        _ = base
        var source = minimalHTMLSource()
        source.ruleBookInfo?.`init` = "id.main-book"
        source.ruleBookInfo?.name = "@js:result"
        let runtime = BookSourceBookInfoRuntime(
            httpClient: client, javaScriptExecutor: SuffixJavaScriptExecutor()
        )
        await XCTAssertThrowsErrorAsync(try await runtime.fetchBookInfo(source: source, book: book())) {
            guard let error = $0 as? BookInfoError,
                  case let .fieldRuleFailed(field, message) = error else {
                return XCTFail("Unexpected \($0)")
            }
            XCTAssertEqual(field, "name")
            XCTAssertTrue(message.contains("structured"))
        }
    }

    func testProductionJavaScriptNetworkHostRemainsUnsupported() async throws {
        let (runtime, _) = runtime(fixture: "html-basic.html")
        var source = htmlSource()
        source.ruleBookInfo?.intro = "@js:java.ajax('/more')"
        await XCTAssertThrowsErrorAsync(try await runtime.fetchBookInfo(source: source, book: book())) {
            XCTAssertEqual($0 as? BookInfoError, .unsupportedJavaScriptNetworkHost)
        }
    }

    func testConcurrentBookInfoFetchesRemainIsolated() async throws {
        let bodyA = Data(#"{"data":{"book":{"name":"A","author":"AA","toc":"/a"}}}"#.utf8)
        let bodyB = Data(#"{"data":{"book":{"name":"B","author":"BB","toc":"/b"}}}"#.utf8)
        let responseA = HTTPResponse(statusCode: 200, data: bodyA, finalURL: try XCTUnwrap(URL(string: "https://a.invalid/info")))
        let responseB = HTTPResponse(statusCode: 200, data: bodyB, finalURL: try XCTUnwrap(URL(string: "https://b.invalid/info")))
        let runtimeA = BookSourceBookInfoRuntime(httpClient: MockHTTPClient(response: responseA))
        let runtimeB = BookSourceBookInfoRuntime(httpClient: MockHTTPClient(response: responseB))
        var sourceA = jsonSource(base: "https://a.invalid")
        var sourceB = jsonSource(base: "https://b.invalid")
        sourceA.ruleBookInfo?.name = #"$.name@put:{"saved":"$.author"}"#
        sourceA.ruleBookInfo?.author = "@get:{saved}"
        sourceB.ruleBookInfo?.name = #"$.name@put:{"saved":"$.author"}"#
        sourceB.ruleBookInfo?.author = "@get:{saved}"
        let isolatedSourceA = sourceA
        let isolatedSourceB = sourceB
        let bookA = book(url: "https://a.invalid/book")
        let bookB = book(url: "https://b.invalid/book")
        async let a = runtimeA.fetchBookInfo(source: isolatedSourceA, book: bookA)
        async let b = runtimeB.fetchBookInfo(source: isolatedSourceB, book: bookB)
        let values = try await (a, b)
        XCTAssertEqual([values.0.name, values.0.author, values.0.tocURL], ["A", "AA", "https://a.invalid/a"])
        XCTAssertEqual([values.1.name, values.1.author, values.1.tocURL], ["B", "BB", "https://b.invalid/b"])
    }

    func testSearchThenBookInfoMockIntegration() async throws {
        let searchBody = Data("<article class='book'><h2>Search A</h2><span class='author'>SA</span><a href='/book/1'>Open</a></article>".utf8)
        let infoBody = try FixtureLoader.data(named: "html-basic.html", directory: "book-info")
        let client = MockHTTPClient(results: [
            .success(HTTPResponse(statusCode: 200, data: searchBody, finalURL: try XCTUnwrap(URL(string: "https://example.invalid/search")))),
            .success(HTTPResponse(statusCode: 200, data: infoBody, finalURL: try XCTUnwrap(URL(string: "https://example.invalid/book/1"))))
        ])
        var source = htmlSource()
        source.searchUrl = "https://example.invalid/search"
        source.ruleSearch = SearchRule(
            bookList: "class.book", name: "tag.h2@text", author: "class.author@text", bookUrl: "tag.a@href"
        )
        let found = try await BookSourceSearchRuntime(httpClient: client)
            .search(source: source, keyword: "A")
        let selected = try XCTUnwrap(found.first)
        let info = try await BookSourceBookInfoRuntime(httpClient: client)
            .fetchBookInfo(source: source, book: selected)
        XCTAssertEqual(info.name, "Book A")
        XCTAssertEqual(info.tocURL, "https://example.invalid/toc/a")
        let requests = await client.requests
        XCTAssertEqual(requests.count, 2)
    }

    func testMalformedHTMLIsRecoverable() async throws {
        let (runtime, _) = runtime(fixture: "html-malformed.html")
        var source = minimalHTMLSource()
        source.ruleBookInfo?.`init` = "id.book"
        let result = try await runtime.fetchBookInfo(source: source, book: book())
        XCTAssertEqual(result.name, "Recoverable")
    }

    private func runtime(
        fixture: String,
        contentType: String = "text/html; charset=utf-8",
        finalURL: String = "https://example.invalid/book/1"
    ) -> (BookSourceBookInfoRuntime, MockHTTPClient) {
        let client = MockHTTPClient(response: try! response(
            fixture: fixture, contentType: contentType, finalURL: finalURL
        ))
        return (BookSourceBookInfoRuntime(httpClient: client), client)
    }

    private func response(
        fixture: String,
        contentType: String = "text/html; charset=utf-8",
        finalURL: String = "https://example.invalid/book/1"
    ) throws -> HTTPResponse {
        HTTPResponse(
            statusCode: 200,
            headers: HTTPHeaders(["Content-Type": contentType]),
            data: try FixtureLoader.data(named: fixture, directory: "book-info"),
            finalURL: try XCTUnwrap(URL(string: finalURL))
        )
    }

    private func book(
        name: String = "Search Name",
        author: String = "Search Author",
        url: String = "https://example.invalid/book/1",
        kind: String? = nil
    ) -> BookSearchResult {
        BookSearchResult(
            name: name, author: author, bookURL: url, kind: kind,
            sourceURL: "https://example.invalid", sourceName: "Source",
            sourceType: 0, sourceOrder: 1
        )
    }

    private func minimalHTMLSource() -> BookSource {
        BookSource(
            bookSourceUrl: "https://example.invalid", bookSourceName: "HTML",
            ruleBookInfo: BookInfoRule(
                name: "tag.h1@text", author: "class.author@text",
                tocUrl: "a.toc@href", canReName: "1"
            )
        )
    }

    private func htmlSource() -> BookSource {
        var source = minimalHTMLSource()
        source.ruleBookInfo?.`init` = "id.book"
        source.ruleBookInfo?.intro = "class.intro@text"
        source.ruleBookInfo?.kind = "class.kind@text"
        source.ruleBookInfo?.wordCount = "class.words@text"
        source.ruleBookInfo?.lastChapter = "class.last@text"
        source.ruleBookInfo?.coverUrl = "tag.img@src"
        return source
    }

    private func jsonSource(base: String = "https://example.invalid") -> BookSource {
        BookSource(
            bookSourceUrl: base, bookSourceName: "JSON",
            ruleBookInfo: BookInfoRule(
                initialRule: "$.data.book", name: "$.name", author: "$.author",
                tocUrl: "$.toc", canReName: "1"
            )
        )
    }
}

private struct SuffixJavaScriptExecutor: RuleJavaScriptExecutor {
    func execute(script: String, context: JavaScriptExecutionContext) throws -> JavaScriptExecutionResult {
        .string(context.result.stringValue + "!")
    }
}

private struct LiteralJavaScriptExecutor: RuleJavaScriptExecutor {
    let value: String

    func execute(script: String, context: JavaScriptExecutionContext) throws -> JavaScriptExecutionResult {
        .string(value)
    }
}

private struct IdentityJavaScriptExecutor: RuleJavaScriptExecutor {
    func execute(script: String, context: JavaScriptExecutionContext) throws -> JavaScriptExecutionResult {
        .string(context.result.stringValue)
    }
}

private func XCTAssertThrowsErrorAsync<T>(
    _ expression: @autoclosure () async throws -> T,
    _ errorHandler: (Error) -> Void
) async {
    do {
        _ = try await expression()
        XCTFail("Expected error")
    } catch {
        errorHandler(error)
    }
}
