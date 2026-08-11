import Foundation
import XCTest
@testable import LegadoCore

final class BookSourceTOCRuntimeTests: XCTestCase {
    func testHTMLTOCEndToEnd() async throws {
        let (runtime, _) = try runtime(fixture: "html-basic.html")
        let chapters = try await runtime.fetchTOC(source: htmlSource(), book: book())

        XCTAssertEqual(chapters.map(\.name), ["Volume One", "Chapter One", "Chapter Two"])
        XCTAssertEqual(chapters.map(\.index), [0, 1, 2])
        XCTAssertEqual(chapters.map(\.isVolume), [true, false, false])
        XCTAssertEqual(chapters.map(\.isVIP), [false, true, false])
        XCTAssertEqual(chapters.map(\.isPay), [false, true, false])
        XCTAssertEqual(chapters.map(\.tag), ["2026-01-01", "2026-01-02", "2026-01-03"])
        XCTAssertEqual(chapters[0].url, "https://example.invalid/books/toc/index")
        XCTAssertEqual(chapters[1].url, "https://example.invalid/books/toc/chapters/1")
        XCTAssertEqual(chapters[2].url, "https://example.invalid/chapters/2")
        XCTAssertEqual(chapters[1].bookURL, "https://example.invalid/book/1")
        XCTAssertEqual(chapters[1].sourceURL, "https://example.invalid")
    }

    func testJSONTOCEndToEndUsesRelativeItemNodes() async throws {
        let (runtime, _) = try runtime(
            fixture: "json-basic.json",
            contentType: "application/json; charset=utf-8"
        )
        let chapters = try await runtime.fetchTOC(source: jsonSource(), book: book())
        XCTAssertEqual(chapters.map(\.name), ["JSON One", "JSON Two"])
        XCTAssertEqual(chapters.map(\.url), [
            "https://example.invalid/json/1",
            "https://example.invalid/books/toc/json/2"
        ])
        XCTAssertEqual(chapters.map(\.isVolume), [false, true])
        XCTAssertEqual(chapters.map(\.isVIP), [true, false])
        XCTAssertEqual(chapters.map(\.isPay), [false, true])
    }

    func testXPathTOCEndToEndUsesRelativeItemNodes() async throws {
        let (runtime, _) = try runtime(fixture: "xpath-basic.html")
        let chapters = try await runtime.fetchTOC(source: xpathSource(), book: book())
        XCTAssertEqual(chapters.map(\.name), ["XPath One", "XPath Two"])
        XCTAssertEqual(chapters.map(\.url), [
            "https://example.invalid/xpath/1",
            "https://example.invalid/books/toc/xpath/2"
        ])
        XCTAssertEqual(chapters.map(\.isVolume), [false, true])
    }

    func testRelativeChapterURLFormsUseSharedResolver() async throws {
        let (runtime, _) = try runtime(fixture: "html-relative-urls.html")
        var source = minimalHTMLSource()
        source.ruleToc?.chapterList = "id.toc@tag.li"
        source.ruleToc?.chapterName = "tag.a@text"
        source.ruleToc?.chapterUrl = "tag.a@href"
        let chapters = try await runtime.fetchTOC(source: source, book: book())
        XCTAssertEqual(chapters.map(\.url), [
            "https://example.invalid/chapter/root",
            "https://example.invalid/books/toc/chapter/relative",
            "https://example.invalid/books/chapter/parent",
            "https://cdn.example.invalid/chapter",
            "https://other.invalid/chapter",
            "https://example.invalid/books/toc/index?chapter=1",
            "https://example.invalid/books/toc/index#anchor"
        ])
    }

    func testRedirectFinalURLIsChapterResolutionBase() async throws {
        let (runtime, _) = try runtime(
            fixture: "html-basic.html",
            finalURL: "https://mirror.example.invalid/redirect/toc/"
        )
        let chapters = try await runtime.fetchTOC(source: htmlSource(), book: book())
        XCTAssertEqual(chapters[0].url, "https://mirror.example.invalid/redirect/toc/")
        XCTAssertEqual(chapters[1].url, "https://mirror.example.invalid/redirect/toc/chapters/1")
    }

    func testMinusChapterListReversesResult() async throws {
        let (runtime, _) = try runtime(fixture: "html-basic.html")
        var source = htmlSource()
        source.ruleToc?.chapterList = "-id.toc@tag.li"
        let chapters = try await runtime.fetchTOC(source: source, book: book())
        XCTAssertEqual(chapters.map(\.name), ["Chapter Two", "Chapter One", "Volume One"])
    }

    func testPlusChapterListKeepsForwardResult() async throws {
        let (runtime, _) = try runtime(fixture: "html-basic.html")
        var source = htmlSource()
        source.ruleToc?.chapterList = "+id.toc@tag.li"
        let chapters = try await runtime.fetchTOC(source: source, book: book())
        XCTAssertEqual(chapters.map(\.name), ["Volume One", "Chapter One", "Chapter Two"])
    }

    func testForwardDeduplicationKeepsLastRawURL() async throws {
        let body = "<ul id='toc'><li><a href='/same'>Old</a></li><li><a href='/b'>B</a></li><li><a href='/same'>New</a></li></ul>"
        let runtime = try runtime(body: body)
        let chapters = try await runtime.fetchTOC(source: minimalListSource(), book: book())
        XCTAssertEqual(chapters.map(\.name), ["B", "New"])
    }

    func testReverseDeduplicationKeepsFirstRawURL() async throws {
        let body = "<ul id='toc'><li><a href='/same'>Old</a></li><li><a href='/b'>B</a></li><li><a href='/same'>New</a></li></ul>"
        let runtime = try runtime(body: body)
        var source = minimalListSource()
        source.ruleToc?.chapterList = "-id.toc@tag.li"
        let chapters = try await runtime.fetchTOC(source: source, book: book())
        XCTAssertEqual(chapters.map(\.name), ["B", "Old"])
    }

    func testEmptyChapterListThrowsTypedError() async throws {
        let (runtime, _) = try runtime(fixture: "empty.html")
        await XCTAssertThrowsErrorAsync(try await runtime.fetchTOC(source: htmlSource(), book: book())) {
            XCTAssertEqual($0 as? TOCError, .emptyChapterList)
        }
    }

    func testMalformedHTMLStillParsesChapters() async throws {
        let (runtime, _) = try runtime(fixture: "html-malformed.html")
        let chapters = try await runtime.fetchTOC(source: minimalListSource(), book: book())
        XCTAssertEqual(chapters.map(\.name), ["One", "Two"])
    }

    func testBlankChapterNameIsFiltered() async throws {
        let runtime = try runtime(body: "<ul id='toc'><li><a href='/empty'></a></li><li><a href='/ok'>OK</a></li></ul>")
        let chapters = try await runtime.fetchTOC(source: minimalListSource(), book: book())
        XCTAssertEqual(chapters.map(\.name), ["OK"])
    }

    func testIsVolumeUsesAndroidTruthSemantics() async throws {
        let values = ["true", "yes", "1", "false", "no", "not", "0", "null", ""]
        let items = values.enumerated().map { index, value in
            "<li><a href='/\(index)'>\(index)</a><i>\(value)</i></li>"
        }.joined()
        let runtime = try runtime(body: "<ul id='toc'>\(items)</ul>")
        var source = minimalListSource()
        source.ruleToc?.isVolume = "tag.i@text"
        let chapters = try await runtime.fetchTOC(source: source, book: book())
        XCTAssertEqual(chapters.map(\.isVolume), [true, true, true, false, false, false, false, false, false])
    }

    func testEmptyVolumeURLUsesPageRedirectURL() async throws {
        let runtime = try runtime(body: "<ul id='toc'><li><a>Volume</a><i>true</i></li></ul>")
        var source = minimalListSource()
        source.ruleToc?.isVolume = "tag.i@text"
        let chapters = try await runtime.fetchTOC(source: source, book: book())
        XCTAssertEqual(chapters[0].url, "https://example.invalid/books/toc/index")
    }

    func testEmptyNonVolumeURLUsesCanonicalTOCURL() async throws {
        let response = try response(
            body: "<ul id='toc'><li><a>Chapter</a></li></ul>",
            finalURL: "https://mirror.example.invalid/toc/"
        )
        let runtime = BookSourceTOCRuntime(httpClient: MockHTTPClient(response: response))
        let chapters = try await runtime.fetchTOC(source: minimalListSource(), book: book())
        XCTAssertEqual(chapters[0].url, "https://example.invalid/books/toc/index")
    }

    func testSingleNextURLLoadsSecondPage() async throws {
        let first = try fixtureResponse("page-1.html", finalURL: "https://example.invalid/toc/page-1")
        let second = try fixtureResponse("page-2.html", finalURL: "https://example.invalid/toc/page-2")
        let client = MockHTTPClient(results: [.success(first), .success(second)])
        var source = minimalListSource()
        source.ruleToc?.nextTocUrl = "id.next@href"
        let runtime = BookSourceTOCRuntime(httpClient: client)
        let chapters = try await runtime.fetchTOC(source: source, book: book(tocURL: "https://example.invalid/toc/page-1"))
        XCTAssertEqual(chapters.map(\.name), ["One", "Two"])
        let requests = await client.requests
        XCTAssertEqual(requests.map { $0.url.absoluteString }, [
            "https://example.invalid/toc/page-1",
            "https://example.invalid/toc/page-2"
        ])
    }

    func testSingleNextURLContinuesAcrossThreePages() async throws {
        let pages = try [
            response(body: page(number: 1, next: "2"), finalURL: "https://example.invalid/toc/1"),
            response(body: page(number: 2, next: "3"), finalURL: "https://example.invalid/toc/2"),
            response(body: page(number: 3), finalURL: "https://example.invalid/toc/3")
        ]
        let client = MockHTTPClient(results: pages.map(Result.success))
        var source = minimalListSource()
        source.ruleToc?.nextTocUrl = "id.next@href"
        let chapters = try await BookSourceTOCRuntime(httpClient: client).fetchTOC(
            source: source,
            book: book(tocURL: "https://example.invalid/toc/1")
        )
        XCTAssertEqual(chapters.map(\.name), ["1", "2", "3"])
    }

    func testRelativeNextURLUsesCurrentPageBase() async throws {
        let next = #"../next/2,{"method":"POST","body":"page=2"}"#
        let first = try response(body: page(number: 1, next: next), finalURL: "https://example.invalid/toc/pages/1")
        let second = try response(body: page(number: 2), finalURL: "https://example.invalid/toc/next/2")
        let client = MockHTTPClient(results: [.success(first), .success(second)])
        var source = minimalListSource()
        source.ruleToc?.nextTocUrl = "id.next@href"
        _ = try await BookSourceTOCRuntime(httpClient: client).fetchTOC(
            source: source,
            book: book(tocURL: "https://example.invalid/toc/pages/1")
        )
        let requests = await client.requests
        XCTAssertEqual(requests.last?.url.absoluteString, "https://example.invalid/toc/next/2")
        XCTAssertEqual(requests.last?.method, .post)
        XCTAssertEqual(String(decoding: try XCTUnwrap(requests.last?.body), as: UTF8.self), "page=2")
    }

    func testNextURLCycleStopsWithoutAnotherRequest() async throws {
        let first = try response(body: page(number: 1, next: "2"), finalURL: "https://example.invalid/toc/1")
        let second = try response(body: page(number: 2, next: "1"), finalURL: "https://example.invalid/toc/2")
        let client = MockHTTPClient(results: [.success(first), .success(second)])
        var source = minimalListSource()
        source.ruleToc?.nextTocUrl = "id.next@href"
        let chapters = try await BookSourceTOCRuntime(httpClient: client).fetchTOC(
            source: source,
            book: book(tocURL: "https://example.invalid/toc/1")
        )
        XCTAssertEqual(chapters.map(\.name), ["1", "2"])
        let requests = await client.requests
        XCTAssertEqual(requests.count, 2)
    }

    func testPaginationSafetyLimitIsExplicit() async throws {
        let first = try response(body: page(number: 1, next: "2"), finalURL: "https://example.invalid/toc/1")
        let second = try response(body: page(number: 2, next: "3"), finalURL: "https://example.invalid/toc/2")
        let client = MockHTTPClient(results: [.success(first), .success(second)])
        var source = minimalListSource()
        source.ruleToc?.nextTocUrl = "id.next@href"
        let runtime = BookSourceTOCRuntime(httpClient: client, maximumPageCount: 2)
        await XCTAssertThrowsErrorAsync(try await runtime.fetchTOC(
            source: source,
            book: book(tocURL: "https://example.invalid/toc/1")
        )) {
            XCTAssertEqual($0 as? TOCError, .paginationLimitExceeded(2))
        }
    }

    func testMultipleNextURLsLoadOneLevelInRuleOrder() async throws {
        let firstBody = "<ul id='toc'><li><a href='/1'>One</a></li></ul><a class='next' href='2'>2</a><a class='next' href='3'>3</a>"
        let responses = try [
            "https://example.invalid/toc/1": response(body: firstBody, finalURL: "https://example.invalid/toc/1"),
            "https://example.invalid/toc/2": response(body: page(number: 2, next: "ignored"), finalURL: "https://example.invalid/toc/2"),
            "https://example.invalid/toc/3": response(body: page(number: 3), finalURL: "https://example.invalid/toc/3")
        ]
        let client = RoutingHTTPClient(responses: responses)
        var source = minimalListSource()
        source.ruleToc?.nextTocUrl = "class.next@href"
        let chapters = try await BookSourceTOCRuntime(httpClient: client).fetchTOC(
            source: source,
            book: book(tocURL: "https://example.invalid/toc/1")
        )
        XCTAssertEqual(chapters.map(\.name), ["One", "2", "3"])
        let requests = await client.requests
        XCTAssertEqual(requests.count, 3)
    }

    func testPOSTTOCURLUsesRequestBuilderOptions() async throws {
        let (baseRuntime, client) = try runtime(fixture: "html-basic.html")
        _ = baseRuntime
        let toc = #"https://example.invalid/toc,{"method":"POST","body":"id=1","headers":{"X-TOC":"yes"}}"#
        _ = try await BookSourceTOCRuntime(httpClient: client).fetchTOC(
            source: htmlSource(),
            book: book(tocURL: toc)
        )
        let requests = await client.requests
        let request = try XCTUnwrap(requests.first)
        XCTAssertEqual(request.method, .post)
        XCTAssertEqual(String(decoding: try XCTUnwrap(request.body), as: UTF8.self), "id=1")
        XCTAssertEqual(request.headers["X-TOC"], "yes")
    }

    func testSourceHeadersFlowThroughRequestBuilder() async throws {
        let (baseRuntime, client) = try runtime(fixture: "html-basic.html")
        _ = baseRuntime
        var source = htmlSource()
        source.header = #"{"X-Source":"toc"}"#
        _ = try await BookSourceTOCRuntime(httpClient: client).fetchTOC(source: source, book: book())
        let requests = await client.requests
        let request = try XCTUnwrap(requests.first)
        XCTAssertEqual(request.headers["X-Source"], "toc")
    }

    func testPutGetSharesContextAcrossFieldsWithinItem() async throws {
        let body = "<ul id='toc'><li><a href='/one'>One</a><b>/one</b><i>true</i></li><li><a href='/two'>Two</a></li></ul>"
        var source = minimalListSource()
        source.ruleToc?.chapterName = #"tag.a@text@put:{"saved":"tag.b@text"}"#
        source.ruleToc?.chapterUrl = #"@get:{saved}@put:{"volume":"tag.i@text"}"#
        source.ruleToc?.isVolume = "@get:{volume}"
        let runtime = try runtime(body: body)
        let chapters = try await runtime.fetchTOC(source: source, book: book())
        XCTAssertEqual(chapters[0].url, "https://example.invalid/one")
        XCTAssertEqual(chapters[1].url, "https://example.invalid/books/toc/index")
        XCTAssertEqual(chapters.map(\.isVolume), [true, false])
    }

    func testChapterItemVariablesDoNotLeakToNextItem() async throws {
        let body = "<ul id='toc'><li><a>One</a><b>/one</b></li><li><a>Two</a></li></ul>"
        var source = minimalListSource()
        source.ruleToc?.chapterName = #"tag.a@text@put:{"saved":"tag.b@text"}"#
        source.ruleToc?.chapterUrl = "@get:{saved}"
        let runtime = try runtime(body: body)
        let chapters = try await runtime.fetchTOC(source: source, book: book())
        XCTAssertEqual(chapters.map(\.url), [
            "https://example.invalid/one",
            "https://example.invalid/books/toc/index"
        ])
    }

    func testPageVariablesCrossSequentialPagination() async throws {
        let firstBody = "<b id='prefix'>Shared</b><ul id='toc'><li><a href='/1'>One</a></li></ul><a id='next' href='2'>next</a>"
        let secondBody = "<b id='prefix'>Updated</b><ul id='toc'><li><a href='/2'>Two</a></li></ul>"
        let client = MockHTTPClient(results: [
            .success(try response(body: firstBody, finalURL: "https://example.invalid/toc/1")),
            .success(try response(body: secondBody, finalURL: "https://example.invalid/toc/2"))
        ])
        var source = minimalListSource()
        source.ruleToc?.chapterList = #"id.toc@tag.li@put:{"prefix":"id.prefix@text"}"#
        source.ruleToc?.chapterName = "@get:{prefix}"
        source.ruleToc?.nextTocUrl = "id.next@href"
        let chapters = try await BookSourceTOCRuntime(httpClient: client).fetchTOC(
            source: source,
            book: book(tocURL: "https://example.invalid/toc/1")
        )
        XCTAssertEqual(chapters.map(\.name), ["Shared", "Updated"])
    }

    func testEmptyPagePutOverwritesPreviousBookVariable() async throws {
        let firstBody = "<b id='prefix'>Shared</b><ul id='toc'><li><a href='/1'>One</a></li></ul><a id='next' href='2'>next</a>"
        let secondBody = "<ul id='toc'><li><a href='/2'>Two</a></li></ul>"
        let client = MockHTTPClient(results: [
            .success(try response(body: firstBody, finalURL: "https://example.invalid/toc/1")),
            .success(try response(body: secondBody, finalURL: "https://example.invalid/toc/2"))
        ])
        var source = minimalListSource()
        source.ruleToc?.chapterList = #"id.toc@tag.li@put:{"prefix":"id.prefix@text"}"#
        source.ruleToc?.chapterName = "tag.a@text"
        source.ruleToc?.chapterUrl = "@get:{prefix}"
        source.ruleToc?.nextTocUrl = "id.next@href"

        let chapters = try await BookSourceTOCRuntime(httpClient: client).fetchTOC(
            source: source,
            book: book(tocURL: "https://example.invalid/toc/1")
        )

        XCTAssertEqual(chapters.map(\.url), [
            "https://example.invalid/toc/Shared",
            "https://example.invalid/toc/2"
        ])
    }

    func testJavaScriptAfterScalarSelectorUsesInjectedExecutor() async throws {
        let (baseRuntime, client) = try runtime(fixture: "html-basic.html")
        _ = baseRuntime
        var source = htmlSource()
        source.ruleToc?.chapterName = "tag.a@text<js>result + '!'</js>"
        let runtime = BookSourceTOCRuntime(httpClient: client, javaScriptExecutor: SuffixJavaScriptExecutor())
        let chapters = try await runtime.fetchTOC(source: source, book: book())
        XCTAssertEqual(chapters[1].name, "Chapter One!")
    }

    func testStructuredItemDirectJavaScriptIsExplicitlyUnsupported() async throws {
        let (baseRuntime, client) = try runtime(fixture: "html-basic.html")
        _ = baseRuntime
        var source = htmlSource()
        source.ruleToc?.chapterName = "@js:result"
        let runtime = BookSourceTOCRuntime(httpClient: client, javaScriptExecutor: SuffixJavaScriptExecutor())
        await XCTAssertThrowsErrorAsync(try await runtime.fetchTOC(source: source, book: book())) {
            guard let error = $0 as? TOCError,
                  case let .chapterFieldRuleFailed(_, field, message) = error else {
                return XCTFail("Unexpected \($0)")
            }
            XCTAssertEqual(field, "chapterName")
            XCTAssertTrue(message.contains("structured"))
        }
    }

    func testProductionJavaScriptNetworkHostRemainsUnsupported() async throws {
        let (runtime, _) = try runtime(fixture: "html-basic.html")
        var source = htmlSource()
        source.ruleToc?.chapterName = "@js:java.ajax('/chapter')"
        await XCTAssertThrowsErrorAsync(try await runtime.fetchTOC(source: source, book: book())) {
            XCTAssertEqual($0 as? TOCError, .unsupportedJavaScriptNetworkHost)
        }
    }

    func testHTTP404BodyStillParses() async throws {
        let response = try fixtureResponse("html-basic.html", statusCode: 404)
        let runtime = BookSourceTOCRuntime(httpClient: MockHTTPClient(response: response))
        let chapters = try await runtime.fetchTOC(source: htmlSource(), book: book())
        XCTAssertEqual(chapters.count, 3)
    }

    func testUnsupportedCharsetIsTypedDecodeFailure() async throws {
        let response = try fixtureResponse("html-basic.html", contentType: "text/html; charset=GBK")
        let runtime = BookSourceTOCRuntime(httpClient: MockHTTPClient(response: response))
        await XCTAssertThrowsErrorAsync(try await runtime.fetchTOC(source: htmlSource(), book: book())) {
            guard let error = $0 as? TOCError,
                  case .responseDecodeFailed = error else { return XCTFail("Unexpected \($0)") }
        }
    }

    func testConcurrentTOCFetchesKeepNodesBasesAndVariablesIsolated() async throws {
        let sourceA = minimalListSource()
        let sourceB = minimalListSource()
        let bookA = book(tocURL: "https://a.invalid/toc")
        let bookB = book(tocURL: "https://b.invalid/toc")
        let responseA = try response(
            body: "<ul id='toc'><li><a href='/a'>A</a></li></ul>",
            finalURL: "https://a.invalid/toc"
        )
        let responseB = try response(
            body: "<ul id='toc'><li><a href='/b'>B</a></li></ul>",
            finalURL: "https://b.invalid/toc"
        )
        let runtimeA = BookSourceTOCRuntime(httpClient: MockHTTPClient(response: responseA))
        let runtimeB = BookSourceTOCRuntime(httpClient: MockHTTPClient(response: responseB))
        async let a = runtimeA.fetchTOC(source: sourceA, book: bookA)
        async let b = runtimeB.fetchTOC(source: sourceB, book: bookB)
        let (chaptersA, chaptersB) = try await (a, b)
        XCTAssertEqual(chaptersA.map(\.url), ["https://a.invalid/a"])
        XCTAssertEqual(chaptersB.map(\.url), ["https://b.invalid/b"])
    }

    func testBookInfoToTOCMockIntegration() async throws {
        let infoHTML = "<article id='book'><h1>Book</h1><a class='toc' href='/toc'>toc</a></article>"
        let tocHTML = "<ul id='toc'><li><a href='/chapter'>Chapter</a></li></ul>"
        let client = RoutingHTTPClient(responses: [
            "https://example.invalid/book/1": try response(body: infoHTML, finalURL: "https://example.invalid/book/1"),
            "https://example.invalid/toc": try response(body: tocHTML, finalURL: "https://example.invalid/toc")
        ])
        var source = minimalListSource()
        source.ruleBookInfo = BookInfoRule(
            initialRule: "id.book", name: "tag.h1@text", tocUrl: "class.toc@href"
        )
        let searchBook = BookSearchResult(
            name: "", author: "", bookURL: "https://example.invalid/book/1",
            sourceURL: source.bookSourceUrl, sourceName: source.bookSourceName,
            sourceType: 0, sourceOrder: 0
        )
        let info = try await BookSourceBookInfoRuntime(httpClient: client).fetchBookInfo(
            source: source,
            book: searchBook
        )
        let chapters = try await BookSourceTOCRuntime(httpClient: client).fetchTOC(source: source, book: info)
        XCTAssertEqual(chapters.map(\.name), ["Chapter"])
    }

    func testSearchToBookInfoToTOCMockIntegration() async throws {
        let searchHTML = "<div class='book'><a href='/book/1'>Book</a></div>"
        let infoHTML = "<article id='book'><h1>Book</h1><a class='toc' href='/toc'>toc</a></article>"
        let tocHTML = "<ul id='toc'><li><a href='/chapter'>Chapter</a></li></ul>"
        let client = RoutingHTTPClient(responses: [
            "https://example.invalid/search?q=x": try response(body: searchHTML, finalURL: "https://example.invalid/search?q=x"),
            "https://example.invalid/book/1": try response(body: infoHTML, finalURL: "https://example.invalid/book/1"),
            "https://example.invalid/toc": try response(body: tocHTML, finalURL: "https://example.invalid/toc")
        ])
        var source = minimalListSource()
        source.searchUrl = "https://example.invalid/search?q={{key}}"
        source.ruleSearch = SearchRule(bookList: "class.book", name: "tag.a@text", bookUrl: "tag.a@href")
        source.ruleBookInfo = BookInfoRule(
            initialRule: "id.book", name: "tag.h1@text", tocUrl: "class.toc@href"
        )
        let search = try await BookSourceSearchRuntime(httpClient: client).search(source: source, keyword: "x")
        let info = try await BookSourceBookInfoRuntime(httpClient: client).fetchBookInfo(
            source: source,
            book: try XCTUnwrap(search.first)
        )
        let chapters = try await BookSourceTOCRuntime(httpClient: client).fetchTOC(source: source, book: info)
        XCTAssertEqual(chapters.map(\.name), ["Chapter"])
    }

    func testInvalidChapterFieldReportsItemAndField() async throws {
        let (runtime, _) = try runtime(fixture: "html-basic.html")
        var source = htmlSource()
        source.ruleToc?.chapterName = "@XPath:["
        await XCTAssertThrowsErrorAsync(try await runtime.fetchTOC(source: source, book: book())) {
            guard let error = $0 as? TOCError,
                  case let .chapterFieldRuleFailed(index, field, _) = error else {
                return XCTFail("Unexpected \($0)")
            }
            XCTAssertEqual(index, 0)
            XCTAssertEqual(field, "chapterName")
        }
    }

    private func runtime(
        fixture: String,
        contentType: String = "text/html; charset=utf-8",
        finalURL: String = "https://example.invalid/books/toc/index"
    ) throws -> (BookSourceTOCRuntime, MockHTTPClient) {
        let response = try fixtureResponse(fixture, contentType: contentType, finalURL: finalURL)
        let client = MockHTTPClient(response: response)
        return (BookSourceTOCRuntime(httpClient: client), client)
    }

    private func runtime(body: String) throws -> BookSourceTOCRuntime {
        BookSourceTOCRuntime(httpClient: MockHTTPClient(response: try response(body: body)))
    }

    private func fixtureResponse(
        _ fixture: String,
        statusCode: Int = 200,
        contentType: String = "text/html; charset=utf-8",
        finalURL: String = "https://example.invalid/books/toc/index"
    ) throws -> HTTPResponse {
        HTTPResponse(
            statusCode: statusCode,
            headers: HTTPHeaders(["Content-Type": contentType]),
            data: try FixtureLoader.data(named: fixture, directory: "toc"),
            finalURL: try XCTUnwrap(URL(string: finalURL))
        )
    }

    private func response(
        body: String,
        statusCode: Int = 200,
        contentType: String = "text/html; charset=utf-8",
        finalURL: String = "https://example.invalid/books/toc/index"
    ) throws -> HTTPResponse {
        HTTPResponse(
            statusCode: statusCode,
            headers: HTTPHeaders(["Content-Type": contentType]),
            data: Data(body.utf8),
            finalURL: try XCTUnwrap(URL(string: finalURL))
        )
    }

    private func htmlSource() -> BookSource {
        BookSource(
            bookSourceUrl: "https://example.invalid",
            bookSourceName: "TOC",
            ruleToc: TocRule(
                chapterList: "id.toc@tag.li",
                chapterName: "class.chapter@text",
                chapterUrl: "class.chapter@href",
                isVolume: "class.volume@text",
                isVip: "class.vip@text",
                isPay: "class.pay@text",
                updateTime: "tag.time@text"
            )
        )
    }

    private func minimalHTMLSource() -> BookSource {
        BookSource(
            bookSourceUrl: "https://example.invalid",
            bookSourceName: "TOC",
            ruleToc: TocRule()
        )
    }

    private func minimalListSource() -> BookSource {
        var source = minimalHTMLSource()
        source.ruleToc?.chapterList = "id.toc@tag.li"
        source.ruleToc?.chapterName = "tag.a@text"
        source.ruleToc?.chapterUrl = "tag.a@href"
        return source
    }

    private func jsonSource() -> BookSource {
        BookSource(
            bookSourceUrl: "https://example.invalid",
            bookSourceName: "JSON TOC",
            ruleToc: TocRule(
                chapterList: "$.data.chapters",
                chapterName: "$.name",
                chapterUrl: "$.url",
                isVolume: "$.volume",
                isVip: "$.vip",
                isPay: "$.pay",
                updateTime: "$.time"
            )
        )
    }

    private func xpathSource() -> BookSource {
        BookSource(
            bookSourceUrl: "https://example.invalid",
            bookSourceName: "XPath TOC",
            ruleToc: TocRule(
                chapterList: "//section[@id='toc']/article",
                chapterName: "@XPath:.//h2/text()",
                chapterUrl: "@XPath:.//a/@href",
                isVolume: "@XPath:.//span[@class='volume']/text()"
            )
        )
    }

    private func book(tocURL: String = "https://example.invalid/books/toc/index") -> BookInfoResult {
        BookInfoResult(
            name: "Book", author: "Author", bookURL: "https://example.invalid/book/1",
            tocURL: tocURL, sourceURL: "https://example.invalid", sourceName: "TOC",
            sourceType: 0, sourceOrder: 0
        )
    }

    private func page(number: Int, next: String? = nil) -> String {
        let link = next.map { "<a id='next' href='\($0)'>next</a>" } ?? ""
        return "<ul id='toc'><li><a href='/chapter/\(number)'>\(number)</a></li></ul>\(link)"
    }
}

private actor RoutingHTTPClient: HTTPClient {
    let responses: [String: HTTPResponse]
    private(set) var requests: [HTTPRequest] = []

    init(responses: [String: HTTPResponse]) {
        self.responses = responses
    }

    func send(_ request: HTTPRequest) async throws -> HTTPResponse {
        requests.append(request)
        guard let response = responses[request.url.absoluteString] else {
            throw HTTPError.transportError("No response for \(request.url.absoluteString)")
        }
        return response
    }
}

private struct SuffixJavaScriptExecutor: RuleJavaScriptExecutor {
    func execute(
        script: String,
        context: JavaScriptExecutionContext
    ) throws -> JavaScriptExecutionResult {
        .string(context.result.stringValue + "!")
    }
}

private func XCTAssertThrowsErrorAsync<T>(
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
