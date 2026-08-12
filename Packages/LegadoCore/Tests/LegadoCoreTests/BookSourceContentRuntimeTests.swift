import Foundation
import XCTest
@testable import LegadoCore

final class BookSourceContentRuntimeTests: XCTestCase {
    func testHTMLContentEndToEnd() async throws {
        let client = MockHTTPClient(response: try fixtureResponse("html-basic.html"))
        let result = try await runtime(client).fetchContent(
            source: source(content: "id.content@html"),
            book: book(),
            chapter: chapter()
        )
        XCTAssertEqual(
            result.content,
            "　　First paragraph\n　　continued\n　　Second paragraph\n　　<img src=\"https://example.invalid/books/images/cover.jpg\">"
        )
        XCTAssertEqual(result.chapterURL, chapter().url)
    }

    func testJSONContentEndToEnd() async throws {
        let client = MockHTTPClient(response: try fixtureResponse(
            "json-basic.json",
            contentType: "application/json; charset=utf-8"
        ))
        let result = try await runtime(client).fetchContent(
            source: source(content: "$.data.content"),
            book: book(),
            chapter: chapter()
        )
        XCTAssertEqual(result.content, "　　JSON first\n　　JSON second")
    }

    func testXPathContentEndToEnd() async throws {
        let client = MockHTTPClient(response: try fixtureResponse("xpath-basic.html"))
        let result = try await runtime(client).fetchContent(
            source: source(content: "@XPath://section[@id='chapter']/outerHtml()"),
            book: book(),
            chapter: chapter()
        )
        XCTAssertEqual(result.content, "　　XPath first\n　　XPath second")
    }

    func testSelectorThenRegexUsesScalarPipeline() async throws {
        let client = MockHTTPClient(response: try response(
            "<div id='content'>prefix VALUE suffix</div>"
        ))
        let result = try await runtime(client).fetchContent(
            source: source(content: "id.content@text##prefix | suffix##"),
            book: book(),
            chapter: chapter()
        )
        XCTAssertEqual(result.content, "VALUE")
    }

    func testSelectorThenJavaScriptUsesScalarPipeline() async throws {
        let client = MockHTTPClient(response: try response("<div id='content'>Value</div>"))
        let result = try await runtime(
            client,
            javaScriptExecutor: ContentSuffixJavaScriptExecutor()
        ).fetchContent(
            source: source(content: "id.content@text<js>result + '!'</js>"),
            book: book(),
            chapter: chapter()
        )
        XCTAssertEqual(result.content, "Value!")
    }

    func testRelativeChapterURLUsesBookTOCAsRequestBase() async throws {
        let client = MockHTTPClient(response: try response(
            "<div id='content'>Relative</div>",
            finalURL: "https://example.invalid/books/chapter/1"
        ))
        let relative = chapter(url: "../chapter/1")
        let result = try await runtime(client).fetchContent(
            source: htmlSource(),
            book: book(tocURL: "https://example.invalid/books/toc/index"),
            chapter: relative
        )
        XCTAssertEqual(result.chapterURL, "../chapter/1")
        let requests = await client.requests
        XCTAssertEqual(requests.first?.url.absoluteString, "https://example.invalid/books/chapter/1")
    }

    func testPOSTChapterURLOptionsRemainIntact() async throws {
        let client = MockHTTPClient(response: try response("<div id='content'>POST</div>"))
        let value = #"https://example.invalid/content,{"method":"POST","body":"id=1","headers":{"X-Chapter":"yes"}}"#
        _ = try await runtime(client).fetchContent(
            source: htmlSource(),
            book: book(),
            chapter: chapter(url: value)
        )
        let requests = await client.requests
        let request = try XCTUnwrap(requests.first)
        XCTAssertEqual(request.method, .post)
        XCTAssertEqual(request.headers["X-Chapter"], "yes")
        XCTAssertEqual(String(decoding: try XCTUnwrap(request.body), as: UTF8.self), "id=1")
    }

    func testRedirectFinalURLResolvesNextPage() async throws {
        let pages = [
            try response(
                "<div id='content'>One</div><a id='next' href='page-2'>next</a>",
                finalURL: "https://mirror.invalid/content/start/"
            ),
            try response(
                "<div id='content'>Two</div>",
                finalURL: "https://mirror.invalid/content/start/page-2"
            )
        ]
        let client = MockHTTPClient(results: pages.map(Result.success))
        var value = htmlSource()
        value.ruleContent?.nextContentUrl = "id.next@href"
        let result = try await runtime(client).fetchContent(
            source: value,
            book: book(),
            chapter: chapter()
        )
        XCTAssertEqual(result.content, "One\nTwo")
        let requests = await client.requests
        XCTAssertEqual(requests.last?.url.absoluteString, "https://mirror.invalid/content/start/page-2")
    }

    func testRedirectFinalURLResolvesRetainedImage() async throws {
        let client = MockHTTPClient(response: try response(
            "<div id='content'><img src='../image.jpg'></div>",
            finalURL: "https://mirror.invalid/content/page/"
        ))
        var value = htmlSource()
        value.ruleContent?.content = "id.content@html"
        let result = try await runtime(client).fetchContent(
            source: value,
            book: book(),
            chapter: chapter()
        )
        XCTAssertEqual(
            result.content,
            "　　<img src=\"https://mirror.invalid/content/image.jpg\">"
        )
    }

    func testHTTP404BodyStillParses() async throws {
        let client = MockHTTPClient(response: try response(
            "<div id='content'>Not found body</div>",
            statusCode: 404
        ))
        let result = try await runtime(client).fetchContent(
            source: htmlSource(),
            book: book(),
            chapter: chapter()
        )
        XCTAssertEqual(result.content, "Not found body")
    }

    func testEmptyExtractedContentThrowsTypedError() async throws {
        let client = MockHTTPClient(response: try response("<div id='other'>Nothing</div>"))
        await XCTAssertThrowsContentError(
            try await runtime(client).fetchContent(
                source: htmlSource(),
                book: book(),
                chapter: chapter()
            )
        ) {
            XCTAssertEqual($0 as? ContentError, .emptyContent)
        }
    }

    func testMissingContentRuleReturnsChapterURLWithoutRequest() async throws {
        let client = MockHTTPClient(error: .transportError("must not request"))
        let result = try await runtime(client).fetchContent(
            source: source(content: nil),
            book: book(),
            chapter: chapter()
        )
        XCTAssertEqual(result.content, chapter().url)
        let requests = await client.requests
        XCTAssertTrue(requests.isEmpty)
    }

    func testMalformedHTMLStillProducesContent() async throws {
        let client = MockHTTPClient(response: try fixtureResponse("html-malformed.html"))
        let result = try await runtime(client).fetchContent(
            source: htmlSource(),
            book: book(),
            chapter: chapter()
        )
        XCTAssertEqual(result.content, "Recoverable Still here")
    }

    func testSinglePageContentMakesOneRequest() async throws {
        let client = MockHTTPClient(response: try response("<div id='content'>Only</div>"))
        let result = try await runtime(client).fetchContent(
            source: htmlSource(),
            book: book(),
            chapter: chapter()
        )
        XCTAssertEqual(result.content, "Only")
        let requests = await client.requests
        XCTAssertEqual(requests.count, 1)
    }

    func testTwoPageContentJoinsInOrder() async throws {
        let client = MockHTTPClient(results: try [
            .success(response(page(1, next: "2"), finalURL: "https://example.invalid/content/1")),
            .success(response(page(2), finalURL: "https://example.invalid/content/2"))
        ])
        let result = try await runtime(client).fetchContent(
            source: pagedSource(),
            book: book(),
            chapter: chapter(url: "https://example.invalid/content/1")
        )
        XCTAssertEqual(result.content, "1\n2")
    }

    func testThreePageContentContinuesSingleURLChain() async throws {
        let client = MockHTTPClient(results: try [
            .success(response(page(1, next: "2"), finalURL: "https://example.invalid/content/1")),
            .success(response(page(2, next: "3"), finalURL: "https://example.invalid/content/2")),
            .success(response(page(3), finalURL: "https://example.invalid/content/3"))
        ])
        let result = try await runtime(client).fetchContent(
            source: pagedSource(),
            book: book(),
            chapter: chapter(url: "https://example.invalid/content/1")
        )
        XCTAssertEqual(result.content, "1\n2\n3")
    }

    func testRelativeNextURLPreservesOptions() async throws {
        let option = #"../next/2,{"method":"POST","body":"page=2"}"#
        let client = MockHTTPClient(results: try [
            .success(response(page(1, next: option), finalURL: "https://example.invalid/content/pages/1")),
            .success(response(page(2), finalURL: "https://example.invalid/content/next/2"))
        ])
        _ = try await runtime(client).fetchContent(
            source: pagedSource(),
            book: book(),
            chapter: chapter(url: "https://example.invalid/content/pages/1")
        )
        let requests = await client.requests
        let request = try XCTUnwrap(requests.last)
        XCTAssertEqual(request.url.absoluteString, "https://example.invalid/content/next/2")
        XCTAssertEqual(request.method, .post)
        XCTAssertEqual(String(decoding: try XCTUnwrap(request.body), as: UTF8.self), "page=2")
    }

    func testAbsoluteNextURLIsNotRebased() async throws {
        let client = MockHTTPClient(results: try [
            .success(response(
                page(1, next: "https://cdn.invalid/page/2"),
                finalURL: "https://example.invalid/content/1"
            )),
            .success(response(page(2), finalURL: "https://cdn.invalid/page/2"))
        ])
        _ = try await runtime(client).fetchContent(
            source: pagedSource(),
            book: book(),
            chapter: chapter(url: "https://example.invalid/content/1")
        )
        let requests = await client.requests
        XCTAssertEqual(requests.last?.url.absoluteString, "https://cdn.invalid/page/2")
    }

    func testNextContentURLCycleStopsBeforeDuplicateRequest() async throws {
        let client = MockHTTPClient(results: try [
            .success(response(page(1, next: "2"), finalURL: "https://example.invalid/content/1")),
            .success(response(page(2, next: "1"), finalURL: "https://example.invalid/content/2"))
        ])
        let result = try await runtime(client).fetchContent(
            source: pagedSource(),
            book: book(),
            chapter: chapter(url: "https://example.invalid/content/1")
        )
        XCTAssertEqual(result.content, "1\n2")
        let requests = await client.requests
        XCTAssertEqual(requests.count, 2)
    }

    func testDuplicateNextURLsAreDeduplicated() async throws {
        let first = "<div id='content'>1</div><a class='next' href='2'>A</a><a class='next' href='2'>B</a>"
        let client = MockHTTPClient(results: try [
            .success(response(first, finalURL: "https://example.invalid/content/1")),
            .success(response(page(2), finalURL: "https://example.invalid/content/2"))
        ])
        var value = pagedSource()
        value.ruleContent?.nextContentUrl = "class.next@href"
        let result = try await runtime(client).fetchContent(
            source: value,
            book: book(),
            chapter: chapter(url: "https://example.invalid/content/1")
        )
        XCTAssertEqual(result.content, "1\n2")
        let requests = await client.requests
        XCTAssertEqual(requests.count, 2)
    }

    func testMultipleNextURLsLoadOnlyOneLevelInRuleOrder() async throws {
        let first = "<div id='content'>1</div><a class='next' href='2'>2</a><a class='next' href='3'>3</a>"
        let client = ContentRoutingHTTPClient(responses: try [
            "https://example.invalid/content/1": response(
                first,
                finalURL: "https://example.invalid/content/1"
            ),
            "https://example.invalid/content/2": response(
                page(2, next: "ignored"),
                finalURL: "https://example.invalid/content/2"
            ),
            "https://example.invalid/content/3": response(
                page(3),
                finalURL: "https://example.invalid/content/3"
            )
        ])
        var value = pagedSource()
        value.ruleContent?.nextContentUrl = "class.next@href"
        let result = try await BookSourceContentRuntime(httpClient: client).fetchContent(
            source: value,
            book: book(),
            chapter: chapter(url: "https://example.invalid/content/1")
        )
        XCTAssertEqual(result.content, "1\n2\n3")
        let requests = await client.requests
        XCTAssertEqual(requests.count, 3)
    }

    func testMaximumPageCountIsExplicitSafetyExtension() async throws {
        let client = MockHTTPClient(results: try [
            .success(response(page(1, next: "2"), finalURL: "https://example.invalid/content/1")),
            .success(response(page(2, next: "3"), finalURL: "https://example.invalid/content/2"))
        ])
        await XCTAssertThrowsContentError(
            try await runtime(client, maximumPageCount: 2).fetchContent(
                source: pagedSource(),
                book: book(),
                chapter: chapter(url: "https://example.invalid/content/1")
            )
        ) {
            XCTAssertEqual($0 as? ContentError, .paginationLimitExceeded(2))
        }
    }

    func testEmptyLaterPageStillReceivesAndroidNewlineSeparator() async throws {
        let client = MockHTTPClient(results: try [
            .success(response(page(1, next: "2"), finalURL: "https://example.invalid/content/1")),
            .success(response("<div id='other'></div>", finalURL: "https://example.invalid/content/2"))
        ])
        let result = try await runtime(client).fetchContent(
            source: pagedSource(),
            book: book(),
            chapter: chapter(url: "https://example.invalid/content/1")
        )
        XCTAssertEqual(result.content, "1\n")
    }

    func testPurificationRunsAfterAllPagesAreMerged() async throws {
        let client = MockHTTPClient(results: try [
            .success(response(pageText("A", next: "2"), finalURL: "https://example.invalid/content/1")),
            .success(response(pageText("B"), finalURL: "https://example.invalid/content/2"))
        ])
        var value = pagedSource()
        value.ruleContent?.replaceRegex = #"##A\nB##Merged"#
        let result = try await runtime(client).fetchContent(
            source: value,
            book: book(),
            chapter: chapter(url: "https://example.invalid/content/1")
        )
        XCTAssertEqual(result.content, "Merged")
    }

    func testContentPutIsVisibleToNextContentURL() async throws {
        let first = "<div id='content'>One</div><span id='saved'>2</span>"
        let client = MockHTTPClient(results: try [
            .success(response(first, finalURL: "https://example.invalid/content/1")),
            .success(response(page(2), finalURL: "https://example.invalid/content/2"))
        ])
        var value = source(content: #"id.content@text@put:{"page":"id.saved@text"}"#)
        value.ruleContent?.nextContentUrl = "@get:{page}"
        let result = try await runtime(client).fetchContent(
            source: value,
            book: book(),
            chapter: chapter(url: "https://example.invalid/content/1")
        )
        XCTAssertEqual(result.content, "One\n2")
    }

    func testChapterVariablesPersistAcrossSequentialPages() async throws {
        let first = "<div id='content'>A</div><span id='saved'>2</span>"
        let second = "<div id='content'>B</div><span id='saved'>3</span>"
        let third = "<div id='content'>C</div>"
        let client = MockHTTPClient(results: try [
            .success(response(first, finalURL: "https://example.invalid/content/1")),
            .success(response(second, finalURL: "https://example.invalid/content/2")),
            .success(response(third, finalURL: "https://example.invalid/content/3"))
        ])
        var value = source(content: #"id.content@text@put:{"saved":"id.saved@text"}"#)
        value.ruleContent?.nextContentUrl = "@get:{saved}"
        let result = try await runtime(client).fetchContent(
            source: value,
            book: book(),
            chapter: chapter(url: "https://example.invalid/content/1")
        )
        XCTAssertEqual(result.content, "A\nB\nC")
    }

    func testEmptyPutOverwritesEarlierChapterVariable() async throws {
        let first = "<div id='content'>A</div><span id='saved'>Old</span><a id='next' href='2'>next</a>"
        let second = "<div id='content'>B</div><span id='output'></span>"
        let client = MockHTTPClient(results: try [
            .success(response(first, finalURL: "https://example.invalid/content/1")),
            .success(response(second, finalURL: "https://example.invalid/content/2"))
        ])
        var value = source(content: #"id.content@text@put:{"saved":"id.saved@text"}"#)
        value.ruleContent?.nextContentUrl = "id.next@href"
        value.ruleContent?.replaceRegex = "@get:{saved}"
        await XCTAssertThrowsContentError(
            try await runtime(client).fetchContent(
                source: value,
                book: book(),
                chapter: chapter(url: "https://example.invalid/content/1")
            )
        ) {
            XCTAssertEqual($0 as? ContentError, .emptyContent)
        }
    }

    func testSeparateContentCallsDoNotShareChapterVariables() async throws {
        let firstClient = MockHTTPClient(response: try response(
            "<div id='content'>A</div><span id='saved'>Private</span>"
        ))
        var writer = source(content: #"id.content@text@put:{"saved":"id.saved@text"}"#)
        _ = try await runtime(firstClient).fetchContent(
            source: writer,
            book: book(),
            chapter: chapter(url: "https://example.invalid/a")
        )

        let secondClient = MockHTTPClient(response: try response("<div id='content'></div>"))
        writer.ruleContent?.content = "@get:{saved}"
        await XCTAssertThrowsContentError(
            try await runtime(secondClient).fetchContent(
                source: writer,
                book: book(),
                chapter: chapter(url: "https://example.invalid/b")
            )
        ) {
            XCTAssertEqual($0 as? ContentError, .emptyContent)
        }
    }

    func testConcurrentContentCallsRemainIsolated() async throws {
        let value = source(
            content: #"@get:{prefix}||id.content@text@put:{"prefix":"id.prefix@text"}"#,
            replaceRegex: "@get:{prefix}"
        )
        let clientA = MockHTTPClient(response: try response(
            "<span id='prefix'>A</span><div id='content'>Body A</div>",
            finalURL: "https://a.invalid/chapter"
        ))
        let clientB = MockHTTPClient(response: try response(
            "<span id='prefix'>B</span><div id='content'>Body B</div>",
            finalURL: "https://b.invalid/chapter"
        ))
        let runtimeA = runtime(clientA)
        let runtimeB = runtime(clientB)
        let bookA = book(tocURL: "https://a.invalid/toc")
        let bookB = book(tocURL: "https://b.invalid/toc")
        let chapterA = chapter(url: "https://a.invalid/chapter")
        let chapterB = chapter(url: "https://b.invalid/chapter")

        async let a = runtimeA.fetchContent(
            source: value,
            book: bookA,
            chapter: chapterA
        )
        async let b = runtimeB.fetchContent(
            source: value,
            book: bookB,
            chapter: chapterB
        )
        let results = try await (a, b)
        XCTAssertEqual(results.0.content, "A")
        XCTAssertEqual(results.1.content, "B")
    }

    func testStructuredJavaScriptInputRemainsUnsupported() async throws {
        let body = "<div id='content'>Value</div>"
        var context = RuleExecutionContext()
        let input = RuleExecutionInput(.string(body))
        let nodeExecutor = RuleNodeExecutor(selectorExecutor: LegadoRuleSelectorExecutor())
        let root = try nodeExecutor.makeRootContext(
            input: input,
            contentIsJSON: false,
            context: &context
        )
        XCTAssertThrowsError(try RuleExecutor(
            selectorExecutor: LegadoRuleSelectorExecutor(),
            javaScriptExecutor: ContentSuffixJavaScriptExecutor()
        ).execute(.javaScript("result"), input: root, context: &context)) {
            XCTAssertEqual(
                $0 as? RuleExecutionError,
                .unsupportedExecutionNode("JavaScript structured input")
            )
        }
    }

    func testProductionJavaScriptNetworkHostRemainsUnsupported() async throws {
        let client = MockHTTPClient(response: try response("<div id='content'>Value</div>"))
        await XCTAssertThrowsContentError(
            try await runtime(
                client,
                javaScriptExecutor: ContentSuffixJavaScriptExecutor()
            ).fetchContent(
                source: source(content: "@js:java.ajax('/page')"),
                book: book(),
                chapter: chapter()
            )
        ) {
            XCTAssertEqual($0 as? ContentError, .unsupportedJavaScriptNetworkHost)
        }
    }

    func testUnsupportedCharsetIsTypedDecodeError() async throws {
        let client = MockHTTPClient(response: try response(
            "<div id='content'>Value</div>",
            contentType: "text/html; charset=unsupported-content-charset"
        ))
        await XCTAssertThrowsContentError(
            try await runtime(client).fetchContent(
                source: htmlSource(),
                book: book(),
                chapter: chapter()
            )
        ) {
            guard let error = $0 as? ContentError,
                  case .responseDecodeFailed = error else {
                return XCTFail("Unexpected error: \($0)")
            }
        }
    }

    func testTOCToContentMockIntegration() async throws {
        let client = MockHTTPClient(results: try [
            .success(response(
                "<ul id='toc'><li><a href='/chapter/1'>One</a></li></ul>",
                finalURL: "https://example.invalid/toc"
            )),
            .success(response(
                "<div id='content'>Integrated</div>",
                finalURL: "https://example.invalid/chapter/1"
            ))
        ])
        var value = htmlSource()
        value.ruleToc = TocRule(
            chapterList: "id.toc@tag.li",
            chapterName: "tag.a@text",
            chapterUrl: "tag.a@href"
        )
        let info = book(tocURL: "https://example.invalid/toc")
        let chapters = try await BookSourceTOCRuntime(httpClient: client).fetchTOC(
            source: value,
            book: info
        )
        let result = try await runtime(client).fetchContent(
            source: value,
            book: info,
            chapter: try XCTUnwrap(chapters.first)
        )
        XCTAssertEqual(result.content, "Integrated")
    }

    func testSearchBookInfoTOCContentMockIntegration() async throws {
        let client = MockHTTPClient(results: try [
            .success(response(
                "<div class='book'><a href='/book/1'>Book</a></div>",
                finalURL: "https://example.invalid/search?q=x"
            )),
            .success(response(
                "<article id='book'><h1>Book</h1><a class='toc' href='/toc'>toc</a></article>",
                finalURL: "https://example.invalid/book/1"
            )),
            .success(response(
                "<ul id='toc'><li><a href='/chapter/1'>One</a></li></ul>",
                finalURL: "https://example.invalid/toc"
            )),
            .success(response(
                "<div id='content'>Complete chain</div>",
                finalURL: "https://example.invalid/chapter/1"
            ))
        ])
        var value = htmlSource()
        value.searchUrl = "https://example.invalid/search?q={{key}}"
        value.ruleSearch = SearchRule(
            bookList: "class.book",
            name: "tag.a@text",
            bookUrl: "tag.a@href"
        )
        value.ruleBookInfo = BookInfoRule(
            initialRule: "id.book",
            name: "tag.h1@text",
            tocUrl: "class.toc@href"
        )
        value.ruleToc = TocRule(
            chapterList: "id.toc@tag.li",
            chapterName: "tag.a@text",
            chapterUrl: "tag.a@href"
        )
        let found = try await BookSourceSearchRuntime(httpClient: client).search(
            source: value,
            keyword: "x"
        )
        let info = try await BookSourceBookInfoRuntime(httpClient: client).fetchBookInfo(
            source: value,
            book: try XCTUnwrap(found.first)
        )
        let chapters = try await BookSourceTOCRuntime(httpClient: client).fetchTOC(
            source: value,
            book: info
        )
        let result = try await runtime(client).fetchContent(
            source: value,
            book: info,
            chapter: try XCTUnwrap(chapters.first)
        )
        XCTAssertEqual(result.content, "Complete chain")
        let requests = await client.requests
        XCTAssertEqual(requests.count, 4)
    }

    private func runtime(
        _ client: MockHTTPClient,
        javaScriptExecutor: (any RuleJavaScriptExecutor)? = nil,
        maximumPageCount: Int = 100
    ) -> BookSourceContentRuntime {
        BookSourceContentRuntime(
            httpClient: client,
            javaScriptExecutor: javaScriptExecutor,
            maximumPageCount: maximumPageCount
        )
    }

    private func source(
        content: String?,
        replaceRegex: String? = nil
    ) -> BookSource {
        BookSource(
            bookSourceUrl: "https://example.invalid",
            bookSourceName: "Content",
            ruleContent: ContentRule(content: content, replaceRegex: replaceRegex)
        )
    }

    private func htmlSource() -> BookSource {
        source(content: "id.content@text")
    }

    private func pagedSource() -> BookSource {
        var value = htmlSource()
        value.ruleContent?.nextContentUrl = "id.next@href"
        return value
    }

    private func book(
        tocURL: String = "https://example.invalid/books/toc/index"
    ) -> BookInfoResult {
        BookInfoResult(
            name: "Book",
            author: "Author",
            bookURL: "https://example.invalid/book/1",
            tocURL: tocURL,
            sourceURL: "https://example.invalid",
            sourceName: "Content",
            sourceType: 0,
            sourceOrder: 0
        )
    }

    private func chapter(
        url: String = "https://example.invalid/books/chapter/1"
    ) -> BookChapterResult {
        BookChapterResult(
            name: "Chapter",
            url: url,
            isVolume: false,
            index: 0,
            bookURL: "https://example.invalid/book/1",
            sourceURL: "https://example.invalid"
        )
    }

    private func fixtureResponse(
        _ fixture: String,
        contentType: String = "text/html; charset=utf-8",
        finalURL: String = "https://example.invalid/books/chapter/1"
    ) throws -> HTTPResponse {
        HTTPResponse(
            statusCode: 200,
            headers: HTTPHeaders(["Content-Type": contentType]),
            data: try FixtureLoader.data(named: fixture, directory: "content"),
            finalURL: try XCTUnwrap(URL(string: finalURL))
        )
    }

    private func response(
        _ body: String,
        statusCode: Int = 200,
        contentType: String = "text/html; charset=utf-8",
        finalURL: String = "https://example.invalid/books/chapter/1"
    ) throws -> HTTPResponse {
        HTTPResponse(
            statusCode: statusCode,
            headers: HTTPHeaders(["Content-Type": contentType]),
            data: Data(body.utf8),
            finalURL: try XCTUnwrap(URL(string: finalURL))
        )
    }

    private func page(_ number: Int, next: String? = nil) -> String {
        pageText(String(number), next: next)
    }

    private func pageText(_ text: String, next: String? = nil) -> String {
        let link = next.map { "<a id='next' href='\($0)'>next</a>" } ?? ""
        return "<div id='content'>\(text)</div>\(link)"
    }
}

private struct ContentSuffixJavaScriptExecutor: RuleJavaScriptExecutor {
    func execute(
        script: String,
        context: JavaScriptExecutionContext
    ) throws -> JavaScriptExecutionResult {
        .string(context.result.stringValue + "!")
    }
}

private actor ContentRoutingHTTPClient: HTTPClient {
    let responses: [String: HTTPResponse]
    private(set) var requests: [HTTPRequest] = []

    init(responses: [String: HTTPResponse]) {
        self.responses = responses
    }

    func send(_ request: HTTPRequest) async throws -> HTTPResponse {
        requests.append(request)
        guard let response = responses[request.url.absoluteString] else {
            throw HTTPError.transportError(
                "No response for \(request.url.absoluteString)"
            )
        }
        return response
    }
}

private func XCTAssertThrowsContentError<T>(
    _ expression: @autoclosure () async throws -> T,
    _ handler: (Error) -> Void = { _ in },
    file: StaticString = #filePath,
    line: UInt = #line
) async {
    do {
        _ = try await expression()
        XCTFail("Expected error", file: file, line: line)
    } catch {
        handler(error)
    }
}
