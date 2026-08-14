import Foundation
import XCTest
@testable import LegadoCore

final class BookSourceCompatibilityRunnerTests: XCTestCase {
    func testImportedChineseFixtureRunsCompleteProductionChain() async throws {
        let client = MockHTTPClient(results: try successfulResponses())
        let report = await BookSourceCompatibilityRunner(httpClient: client).run(
            sourceJSON: try sourceJSON(),
            keyword: "科幻"
        )

        XCTAssertTrue(report.isSuccessful)
        XCTAssertNil(report.failure)
        XCTAssertEqual(report.source?.bookSourceName, "中文兼容夹具")
        XCTAssertEqual(report.source?.extraFields["fixtureRevision"], .string("desensitized-v1"))
        XCTAssertEqual(report.searchResults.map(\.name), ["三体"])
        XCTAssertEqual(report.selectedSearchResult?.author, "刘慈欣")
        XCTAssertEqual(report.bookInfo?.name, "三体")
        XCTAssertEqual(report.bookInfo?.intro, "地球往事三部曲")
        XCTAssertEqual(report.bookInfo?.tocURL, "https://fixture.invalid/book/three/chapters")
        XCTAssertEqual(report.chapters.map(\.name), ["第一章 科学边界"])
        XCTAssertEqual(report.selectedChapter?.url, "https://fixture.invalid/book/three/chapter/1")
        XCTAssertEqual(report.content?.content, "宇宙很大，生活更大。")

        let requests = await client.requests
        XCTAssertEqual(requests.count, 4)
        XCTAssertEqual(
            requests[0].url.absoluteString,
            "https://fixture.invalid/search?keyword=%BF%C6%BB%C3"
        )
        XCTAssertEqual(requests.map(\.method), [.get, .get, .get, .get])
    }

    func testImportFailureIsReportedWithoutSendingRequest() async {
        let client = MockHTTPClient(error: .transportError("must not execute"))
        let report = await BookSourceCompatibilityRunner(httpClient: client).run(
            sourceJSON: Data("not-json".utf8),
            keyword: "科幻"
        )
        XCTAssertEqual(report.failure?.stage, .import)
        XCTAssertEqual(report.failure?.operation, .import)
        let requests = await client.requests
        XCTAssertTrue(requests.isEmpty)
    }

    func testRequestFailureRetainsSearchOperationAndRedactsSecret() async throws {
        let client = MockHTTPClient(error: .transportError("token=private-value"))
        let report = await BookSourceCompatibilityRunner(httpClient: client).run(
            sourceJSON: try sourceJSON(),
            keyword: "科幻"
        )
        XCTAssertEqual(report.failure?.stage, .request)
        XCTAssertEqual(report.failure?.operation, .search)
        XCTAssertFalse(report.failure?.message.contains("private-value") == true)
        XCTAssertTrue(report.failure?.message.contains("<redacted>") == true)
    }

    func testCharsetFailureCategoryRetainsSearchOperation() async throws {
        let response = try fixtureResponse(
            "search.html",
            url: "https://fixture.invalid/search",
            charset: "x-private"
        )
        let report = await BookSourceCompatibilityRunner(
            httpClient: MockHTTPClient(response: response)
        ).run(sourceJSON: try sourceJSON(), keyword: "科幻")
        XCTAssertEqual(report.failure?.stage, .charset)
        XCTAssertEqual(report.failure?.operation, .search)
    }

    func testRuleParserFailureCategory() async throws {
        let json = try replacing(
            #""bookList": "class.book""#,
            with: #""bookList": "$[?(@.name""#
        )
        let report = await BookSourceCompatibilityRunner(
            httpClient: MockHTTPClient(response: try fixtureResponse("search.html", url: "https://fixture.invalid/search"))
        ).run(sourceJSON: json, keyword: "科幻")
        XCTAssertEqual(report.failure?.stage, .ruleParser)
        XCTAssertEqual(report.failure?.operation, .search)
    }

    func testSelectorFailureCategory() async throws {
        let json = try replacing(
            #""bookList": "class.book""#,
            with: #""bookList": "@CSS:h1@text""#
        )
        let report = await BookSourceCompatibilityRunner(
            httpClient: MockHTTPClient(response: try fixtureResponse("search.html", url: "https://fixture.invalid/search"))
        ).run(sourceJSON: json, keyword: "科幻")
        XCTAssertEqual(report.failure?.stage, .selector)
        XCTAssertEqual(report.failure?.operation, .search)
    }

    func testJavaScriptFailureCategory() async throws {
        let json = try replacing(#""name": "class.name@text""#, with: #""name": "@js:result""#)
        let report = await BookSourceCompatibilityRunner(
            httpClient: MockHTTPClient(response: try fixtureResponse("search.html", url: "https://fixture.invalid/search"))
        ).run(sourceJSON: json, keyword: "科幻")
        XCTAssertEqual(report.failure?.stage, .javascript)
        XCTAssertEqual(report.failure?.operation, .search)
    }

    func testProductionJavaScriptNetworkHostRemainsUnsupported() async throws {
        let json = try replacing(
            "https://fixture.invalid/search?keyword={{key}}",
            with: "https://fixture.invalid/@js:java.ajax('/search')"
        )
        let client = MockHTTPClient(error: .transportError("must not execute"))
        let report = await BookSourceCompatibilityRunner(httpClient: client).run(
            sourceJSON: json,
            keyword: "科幻"
        )
        XCTAssertEqual(report.failure?.stage, .unsupportedCapability)
        XCTAssertEqual(report.failure?.operation, .search)
        let requests = await client.requests
        XCTAssertTrue(requests.isEmpty)
    }

    func testTOCAndContentBusinessFailuresKeepTheirOperation() async throws {
        var tocResponses = try successfulResponses()
        tocResponses[2] = .success(try fixtureResponse("empty.html", directory: "toc", url: "https://fixture.invalid/toc"))
        let toc = await BookSourceCompatibilityRunner(
            httpClient: MockHTTPClient(results: Array(tocResponses.prefix(3)))
        ).run(sourceJSON: try sourceJSON(), keyword: "科幻")
        XCTAssertEqual(toc.failure?.stage, .toc)
        XCTAssertEqual(toc.failure?.operation, .toc)

        var contentResponses = try successfulResponses()
        contentResponses[3] = .success(try fixtureResponse("empty.html", directory: "content", url: "https://fixture.invalid/content"))
        let content = await BookSourceCompatibilityRunner(
            httpClient: MockHTTPClient(results: contentResponses)
        ).run(sourceJSON: try sourceJSON(), keyword: "科幻")
        XCTAssertEqual(content.failure?.stage, .content)
        XCTAssertEqual(content.failure?.operation, .content)
    }

    private func successfulResponses() throws -> [Result<HTTPResponse, HTTPError>] {
        [
            .success(try fixtureResponse("search.html", url: "https://fixture.invalid/search")),
            .success(try fixtureResponse("book-info.html", url: "https://fixture.invalid/book/three")),
            .success(try fixtureResponse("toc.html", url: "https://fixture.invalid/book/three/chapters")),
            .success(try fixtureResponse("content.html", url: "https://fixture.invalid/book/three/chapter/1"))
        ]
    }

    private func fixtureResponse(
        _ fixture: String,
        directory: String = "compatibility",
        url: String,
        charset: String = "GBK"
    ) throws -> HTTPResponse {
        let text = String(
            decoding: try FixtureLoader.data(named: fixture, directory: directory),
            as: UTF8.self
        )
        let data = charset == "x-private"
            ? Data(text.utf8)
            : try FoundationTextEncoder().encode(text, charset: charset)
        return HTTPResponse(
            statusCode: 200,
            headers: HTTPHeaders(["Content-Type": "text/html; charset=\(charset)"]),
            data: data,
            finalURL: try XCTUnwrap(URL(string: url))
        )
    }

    private func sourceJSON() throws -> Data {
        try FixtureLoader.data(named: "chinese-source.json", directory: "compatibility")
    }

    private func replacing(_ target: String, with replacement: String) throws -> Data {
        let original = String(decoding: try sourceJSON(), as: UTF8.self)
        return Data(original.replacingOccurrences(of: target, with: replacement).utf8)
    }
}
