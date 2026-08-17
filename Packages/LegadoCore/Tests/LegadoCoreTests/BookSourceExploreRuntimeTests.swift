import Foundation
import XCTest
@testable import LegadoCore

final class BookSourceExploreRuntimeTests: XCTestCase {
    func testSingleExploreCategory() throws {
        XCTAssertEqual(
            try ExploreURLParser().parse("玄幻::/category/fantasy"),
            [ExploreKind(title: "玄幻", url: "/category/fantasy")]
        )
    }

    func testMultipleCategoriesAndHeaderKindsRemainFlatAndOrdered() throws {
        XCTAssertEqual(
            try ExploreURLParser().parse("热门&&男频\n玄幻::/x&&科幻::/s"),
            [
                ExploreKind(title: "热门"),
                ExploreKind(title: "男频"),
                ExploreKind(title: "玄幻", url: "/x"),
                ExploreKind(title: "科幻", url: "/s")
            ]
        )
    }

    func testJSONCategoriesPreserveStyleWithAndroidDefaults() throws {
        let value = #"[{"title":"排行","url":"/rank","style":{"layout_flexGrow":1,"layout_wrapBefore":true}}]"#
        let kinds = try ExploreURLParser().parse(value)
        XCTAssertEqual(kinds.first?.title, "排行")
        XCTAssertEqual(kinds.first?.style?.layoutFlexGrow, 1)
        XCTAssertEqual(kinds.first?.style?.layoutFlexShrink, 1)
        XCTAssertEqual(kinds.first?.style?.layoutAlignSelf, "auto")
        XCTAssertEqual(kinds.first?.style?.layoutWrapBefore, true)
    }

    func testJavaScriptCategoryDefinitionUsesInjectedExecutor() throws {
        let parser = ExploreURLParser(javaScriptExecutor: ExploreFakeJavaScriptExecutor())
        XCTAssertEqual(
            try parser.parse("@js:categories"),
            [ExploreKind(title: "JS 分类", url: "/js")]
        )
    }

    func testCategoryJavaScriptNetworkHostRemainsUnsupported() throws {
        XCTAssertThrowsError(
            try ExploreURLParser(javaScriptExecutor: ExploreFakeJavaScriptExecutor())
                .parse("@js:java.ajax('/categories')")
        ) { error in
            XCTAssertEqual(error as? ExploreURLParserError, .unsupportedJavaScriptNetworkHost)
        }
    }

    func testHTMLExploreUsesExploreRules() async throws {
        let (runtime, _) = runtime(fixture: "html.html")
        let results = try await runtime.explore(source: htmlSource(), url: "/category?page={{page}}", page: 1)
        XCTAssertEqual(results.map(\.name), ["Explore A", "Explore B"])
        XCTAssertEqual(results.map(\.author), ["Author A", "Author B"])
    }

    func testJSONExplore() async throws {
        let (runtime, _) = runtime(
            fixture: "json.json",
            contentType: "application/json",
            finalURL: "https://api.example.invalid/category/list"
        )
        let results = try await runtime.explore(source: jsonSource(), url: "/category")
        XCTAssertEqual(results.map(\.name), ["JSON A", "JSON B"])
        XCTAssertEqual(results.map(\.bookURL), [
            "https://api.example.invalid/book/ja",
            "https://api.example.invalid/book/jb"
        ])
    }

    func testXPathExplore() async throws {
        let (runtime, _) = runtime(fixture: "xpath.html")
        var source = htmlSource()
        source.ruleExplore = ExploreRule(
            bookList: "@XPath://article",
            name: "@XPath:.//h2/text()",
            author: "@XPath:.//span[@class='author']/text()",
            bookUrl: "@XPath:.//a/@href"
        )
        let results = try await runtime.explore(source: source, url: "/xpath")
        XCTAssertEqual(results.map(\.name), ["XPath A", "XPath B"])
        XCTAssertEqual(results.map(\.author), ["XA", "XB"])
    }

    func testRedirectFinalURLIsBaseForRelativeBookAndCoverURLs() async throws {
        let (runtime, _) = runtime(
            fixture: "html.html",
            finalURL: "https://mirror.example.invalid/categories/current/list"
        )
        let results = try await runtime.explore(source: htmlSource(), url: "/category")
        XCTAssertEqual(results[0].bookURL, "https://mirror.example.invalid/categories/book/a")
        XCTAssertEqual(results[0].coverURL, "https://mirror.example.invalid/covers/a.jpg")
        XCTAssertEqual(results[1].coverURL, "https://cdn.example.invalid/b.jpg")
    }

    func testPageAlternativesCoverFirstSecondAndRepeatedLastURL() async throws {
        let (runtime, client) = runtime(
            responses: [
                try response(fixture: "empty.html"),
                try response(fixture: "empty.html"),
                try response(fixture: "empty.html")
            ]
        )
        let source = htmlSource()
        _ = try await runtime.explore(source: source, url: "/<first,second,last>", page: 1)
        _ = try await runtime.explore(source: source, url: "/<first,second,last>", page: 2)
        _ = try await runtime.explore(source: source, url: "/<first,second,last>", page: 4)
        let requests = await client.requests
        XCTAssertEqual(requests.map(\.url.absoluteString), [
            "https://example.invalid/first",
            "https://example.invalid/second",
            "https://example.invalid/last"
        ])
    }

    func testChineseQueryIsEncodedByRequestBuilder() async throws {
        let (runtime, client) = runtime(fixture: "empty.html")
        _ = try await runtime.explore(source: htmlSource(), url: "/category?name=科幻&page={{page}}", page: 2)
        let requests = await client.requests
        XCTAssertEqual(
            requests.first?.url.absoluteString,
            "https://example.invalid/category?name=%E7%A7%91%E5%B9%BB&page=2"
        )
    }

    func testPOSTExploreUsesURLRequestOptions() async throws {
        let (runtime, client) = runtime(fixture: "empty.html")
        let url = #"/category,{"method":"POST","body":"page={{page}}&kind=科幻","headers":{"X-Explore":"1"}}"#
        _ = try await runtime.explore(source: htmlSource(), url: url, page: 2)
        let requests = await client.requests
        let request = try XCTUnwrap(requests.first)
        XCTAssertEqual(request.method, .post)
        XCTAssertEqual(request.headers["X-Explore"], "1")
        XCTAssertEqual(String(decoding: try XCTUnwrap(request.body), as: UTF8.self), "page=2&kind=%E7%A7%91%E5%B9%BB")
    }

    func testURLPutVariablesFlowIntoExploreItemRules() async throws {
        let (runtime, _) = runtime(fixture: "html.html")
        var source = htmlSource()
        source.ruleExplore?.name = "@get:{saved}"
        let url = #"/category@put:{"saved":"From URL"}"#
        let results = try await runtime.explore(source: source, url: url)
        XCTAssertEqual(results.map(\.name), ["From URL", "From URL"])
    }

    func testPutGetAcrossFieldsRemainIsolatedPerItem() async throws {
        let (runtime, _) = runtime(fixture: "html.html")
        var source = htmlSource()
        source.ruleExplore?.name = #"class.name@text@put:{"saved":"class.author@text"}"#
        source.ruleExplore?.author = "@get:{saved}"
        let results = try await runtime.explore(source: source, url: "/category")
        XCTAssertEqual(results.map(\.author), ["Author A", "Author B"])
    }

    func testPureJavaScriptRequestAndFieldRules() async throws {
        let response = try response(fixture: "html.html")
        let client = MockHTTPClient(response: response)
        let executor = ExploreFakeJavaScriptExecutor()
        let runtime = BookSourceExploreRuntime(
            httpClient: client,
            javaScriptExecutor: executor
        )
        var source = htmlSource()
        source.ruleExplore?.name = "class.name@text<js>append</js>"
        let results = try await runtime.explore(source: source, url: "@js:requestURL", page: 3)
        XCTAssertEqual(results.first?.name, "Explore A!")
        let requests = await client.requests
        XCTAssertEqual(requests.first?.url.absoluteString, "https://example.invalid/js?page=3")
    }

    func testOptionJavaScriptCanRewriteExploreURL() async throws {
        let response = try response(fixture: "empty.html")
        let client = MockHTTPClient(response: response)
        let runtime = BookSourceExploreRuntime(
            httpClient: client,
            javaScriptExecutor: ExploreFakeJavaScriptExecutor()
        )
        let url = #"/before,{"js":"optionURL"}"#
        _ = try await runtime.explore(source: htmlSource(), url: url, page: 2)
        let requests = await client.requests
        XCTAssertEqual(requests.first?.url.absoluteString, "https://example.invalid/option?page=2")
    }

    func testExploreFallsBackToSearchRulesWhenExploreBookListIsBlank() async throws {
        let (runtime, _) = runtime(fixture: "html.html")
        var source = htmlSource()
        source.ruleSearch = SearchRule(
            bookList: "class.book",
            name: "class.name@text",
            author: "class.author@text",
            bookUrl: "class.name@href"
        )
        source.ruleExplore = ExploreRule()
        let results = try await runtime.explore(source: source, url: "/category")
        XCTAssertEqual(results.map(\.name), ["Explore A", "Explore B"])
    }

    func testEmptyExploreListReturnsEmptyArray() async throws {
        let (runtime, _) = runtime(fixture: "empty.html")
        let results = try await runtime.explore(source: htmlSource(), url: "/empty")
        XCTAssertEqual(results, [])
    }

    func testHTTP404BodyStillParses() async throws {
        var value = try response(fixture: "html.html")
        value = HTTPResponse(
            statusCode: 404,
            headers: value.headers,
            data: value.data,
            finalURL: value.finalURL
        )
        let runtime = BookSourceExploreRuntime(httpClient: MockHTTPClient(response: value))
        let results = try await runtime.explore(source: htmlSource(), url: "/missing")
        XCTAssertEqual(results.first?.name, "Explore A")
    }

    func testConcurrentExploreContextsRemainIsolated() async throws {
        let firstClient = MockHTTPClient(response: try response(fixture: "html.html"))
        let secondClient = MockHTTPClient(response: try response(
            fixture: "json.json",
            contentType: "application/json",
            finalURL: "https://api.example.invalid/list"
        ))
        let firstRuntime = BookSourceExploreRuntime(httpClient: firstClient)
        let secondRuntime = BookSourceExploreRuntime(httpClient: secondClient)
        let firstSource = htmlSource()
        let secondSource = jsonSource()
        async let first = firstRuntime.explore(
            source: firstSource,
            url: #"/a@put:{"scope":"html"}"#
        )
        async let second = secondRuntime.explore(
            source: secondSource,
            url: #"/b@put:{"scope":"json"}"#
        )
        let values = try await (first, second)
        XCTAssertEqual(values.0.map(\.name), ["Explore A", "Explore B"])
        XCTAssertEqual(values.1.map(\.name), ["JSON A", "JSON B"])
    }

    func testGBKExploreResponseUsesExistingTextDecoder() async throws {
        let text = String(decoding: try FixtureLoader.data(named: "html.html", directory: "explore"), as: UTF8.self)
            .replacingOccurrences(of: "Explore A", with: "科幻甲")
        let data = try FoundationTextEncoder().encode(text, charset: "GBK")
        let response = HTTPResponse(
            statusCode: 200,
            headers: HTTPHeaders(["Content-Type": "text/html; charset=GBK"]),
            data: data,
            finalURL: try XCTUnwrap(URL(string: "https://example.invalid/category"))
        )
        let runtime = BookSourceExploreRuntime(httpClient: MockHTTPClient(response: response))
        let results = try await runtime.explore(source: htmlSource(), url: "/category")
        XCTAssertEqual(results.first?.name, "科幻甲")
    }

    func testProductionJavaScriptNetworkHostRemainsUnsupported() async throws {
        let client = MockHTTPClient(error: .transportError("must not execute"))
        let runtime = BookSourceExploreRuntime(httpClient: client)
        do {
            _ = try await runtime.explore(source: htmlSource(), url: "@js:java.ajax('/category')")
            XCTFail("Expected unsupported capability")
        } catch {
            XCTAssertEqual(error as? BookExploreError, .unsupportedJavaScriptNetworkHost)
        }
        let requests = await client.requests
        XCTAssertTrue(requests.isEmpty)
    }

    func testLoginCheckJavaScriptIsNotSilentlyIgnored() async throws {
        let client = MockHTTPClient(error: .transportError("must not execute"))
        let runtime = BookSourceExploreRuntime(httpClient: client)
        var source = htmlSource()
        source.loginCheckJs = "result"
        do {
            _ = try await runtime.explore(source: source, url: "/category")
            XCTFail("Expected unsupported login boundary")
        } catch {
            XCTAssertEqual(error as? BookExploreError, .unsupportedWebView)
        }
        let requests = await client.requests
        XCTAssertTrue(requests.isEmpty)
    }

    func testExploreBookContinuesThroughBookInfoTOCAndContent() async throws {
        var source = try JSONDecoder().decode(
            BookSource.self,
            from: FixtureLoader.data(named: "chinese-source.json", directory: "compatibility")
        )
        source.exploreUrl = "分类::https://fixture.invalid/explore"
        source.ruleExplore = ExploreRule(
            bookList: "class.book",
            name: "class.name@text",
            author: "class.author@text",
            bookUrl: "class.name@href"
        )
        let responses: [Result<HTTPResponse, HTTPError>] = [
            .success(try compatibilityResponse("search.html", url: "https://fixture.invalid/explore")),
            .success(try compatibilityResponse("book-info.html", url: "https://fixture.invalid/book/three")),
            .success(try compatibilityResponse("toc.html", url: "https://fixture.invalid/book/three/chapters")),
            .success(try compatibilityResponse("content.html", url: "https://fixture.invalid/book/three/chapter/1"))
        ]
        let client = MockHTTPClient(results: responses)
        let explored = try await BookSourceExploreRuntime(httpClient: client)
            .explore(source: source, url: "https://fixture.invalid/explore")
        let book = try await BookSourceBookInfoRuntime(httpClient: client)
            .fetchBookInfo(source: source, book: try XCTUnwrap(explored.first))
        let chapters = try await BookSourceTOCRuntime(httpClient: client)
            .fetchTOC(source: source, book: book)
        let content = try await BookSourceContentRuntime(httpClient: client)
            .fetchContent(source: source, book: book, chapter: try XCTUnwrap(chapters.first))
        XCTAssertEqual(book.name, "三体")
        XCTAssertEqual(chapters.first?.name, "第一章 科学边界")
        XCTAssertEqual(content.content, "宇宙很大，生活更大。")
    }

    private func runtime(
        fixture: String,
        contentType: String = "text/html; charset=utf-8",
        finalURL: String = "https://example.invalid/category/list"
    ) -> (BookSourceExploreRuntime, MockHTTPClient) {
        runtime(responses: [try! response(fixture: fixture, contentType: contentType, finalURL: finalURL)])
    }

    private func runtime(
        responses: [HTTPResponse]
    ) -> (BookSourceExploreRuntime, MockHTTPClient) {
        let client = MockHTTPClient(results: responses.map { .success($0) })
        return (BookSourceExploreRuntime(httpClient: client), client)
    }

    private func response(
        fixture: String,
        contentType: String = "text/html; charset=utf-8",
        finalURL: String = "https://example.invalid/category/list"
    ) throws -> HTTPResponse {
        HTTPResponse(
            statusCode: 200,
            headers: HTTPHeaders(["Content-Type": contentType]),
            data: try FixtureLoader.data(named: fixture, directory: "explore"),
            finalURL: try XCTUnwrap(URL(string: finalURL))
        )
    }

    private func compatibilityResponse(_ fixture: String, url: String) throws -> HTTPResponse {
        HTTPResponse(
            statusCode: 200,
            headers: HTTPHeaders(["Content-Type": "text/html; charset=utf-8"]),
            data: try FixtureLoader.data(named: fixture, directory: "compatibility"),
            finalURL: try XCTUnwrap(URL(string: url))
        )
    }

    private func htmlSource() -> BookSource {
        BookSource(
            bookSourceUrl: "https://example.invalid",
            bookSourceName: "Explore HTML",
            customOrder: 4,
            exploreUrl: "分类::/category",
            ruleExplore: ExploreRule(
                bookList: "class.book",
                name: "class.name@text",
                author: "class.author@text",
                bookUrl: "class.name@href",
                coverUrl: "tag.img@src"
            )
        )
    }

    private func jsonSource() -> BookSource {
        BookSource(
            bookSourceUrl: "https://api.example.invalid",
            bookSourceName: "Explore JSON",
            exploreUrl: "分类::/category",
            ruleExplore: ExploreRule(
                bookList: "$.items[*]",
                name: "$.name",
                author: "$.author",
                bookUrl: "$.url",
                coverUrl: "$.cover"
            )
        )
    }
}

private struct ExploreFakeJavaScriptExecutor: RuleJavaScriptExecutor {
    func execute(script: String, context: JavaScriptExecutionContext) throws -> JavaScriptExecutionResult {
        switch script.trimmingCharacters(in: .whitespacesAndNewlines) {
        case "categories":
            .string(#"[{"title":"JS 分类","url":"/js"}]"#)
        case "requestURL":
            .string("https://example.invalid/js?page=\(context.temporaryVariables["page"] ?? "")")
        case "optionURL":
            .string("https://example.invalid/option?page=\(context.temporaryVariables["page"] ?? "")")
        default:
            .string(context.result.stringValue + "!")
        }
    }
}
