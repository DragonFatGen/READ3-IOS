import Foundation
import XCTest
@testable import LegadoCore

final class SearchDiagnosticTests: XCTestCase {
    private let detail = """
    <html><head><meta property="og:type" content="book">
    <meta property="og:title" content="Invented title"></head><body>
    <article class="item"><h1>Invented title</h1><a href="/book/1">Details</a></article>
    </body></html>
    """

    func testDirectDetailResponseExtractsOneBookAndSafeMetadata() async throws {
        let response = response(detail, redirected: true)
        var diagnostic = SearchDiagnostic()
        let books = try await BookSourceSearchRuntime(httpClient: MockHTTPClient(response: response))
            .search(source: source(), keyword: "Invented title", diagnostic: &diagnostic)
        XCTAssertEqual(books.map(\.name), ["Invented title"])
        XCTAssertEqual(diagnostic.lastStage, .parsed)
        XCTAssertEqual(diagnostic.bookListMatchedCount, 1)
        XCTAssertEqual(diagnostic.finalResultCount, 1)
        XCTAssertEqual(diagnostic.missingNameCount, 0)
        XCTAssertEqual(diagnostic.missingBookURLCount, 0)
        XCTAssertEqual(diagnostic.filteredItemCount, 0)
        XCTAssertEqual(diagnostic.ruleThrew, false)
        XCTAssertEqual(diagnostic.responseStatusCode, 200)
        XCTAssertEqual(diagnostic.responseContentType, .html)
        XCTAssertEqual(diagnostic.responseByteCount, Data(detail.utf8).count)
        XCTAssertEqual(diagnostic.responseRedirected, true)
        XCTAssertEqual(diagnostic.pageHint, .bookDetail)
        XCTAssertNil(diagnostic.indexInRange) // Runtime does not select a book.
        let json = String(decoding: try JSONEncoder().encode(diagnostic), as: UTF8.self)
        XCTAssertFalse(json.contains("private-"))
        XCTAssertFalse(json.contains("https://"))
        XCTAssertFalse(json.contains("Invented title"))
    }

    func testSearchFormIsARealZeroWithAnOutOfRangeIndex() async throws {
        let html = "<form role='search' action='?action=login'><input type='search'></form>"
        let report = await BookSourceCompatibilityRunner(httpClient: MockHTTPClient(response: response(html)))
            .run(sourceJSON: try JSONEncoder().encode(source()), keyword: "x")
        let diagnostic = try XCTUnwrap(report.searchDiagnostic)
        XCTAssertEqual(diagnostic.lastStage, .resultSelection)
        XCTAssertEqual(diagnostic.pageHint, .searchForm)
        XCTAssertEqual(diagnostic.bookListMatchedCount, 0)
        XCTAssertEqual(diagnostic.finalResultCount, 0)
        XCTAssertEqual(diagnostic.missingNameCount, 0)
        XCTAssertEqual(diagnostic.ruleThrew, false)
        XCTAssertEqual(diagnostic.requestedBookIndex, 0)
        XCTAssertEqual(diagnostic.indexInRange, false)
        XCTAssertEqual(report.failure?.stage, .search)
    }

    func testMissingNamesFilterButDoNotExecuteBookURLForSkippedNodes() async throws {
        let html = "<article class='item'><a href='/ignored'>No name</a></article>" + detail
        var diagnostic = SearchDiagnostic()
        let books = try await BookSourceSearchRuntime(httpClient: MockHTTPClient(response: response(html)))
            .search(source: source(), keyword: "x", diagnostic: &diagnostic)
        XCTAssertEqual(books.count, 1)
        XCTAssertEqual(diagnostic.bookListMatchedCount, 2)
        XCTAssertEqual(diagnostic.missingNameCount, 1)
        XCTAssertEqual(diagnostic.filteredItemCount, 1)
        XCTAssertEqual(diagnostic.finalResultCount, 1)
        XCTAssertNil(diagnostic.missingBookURLCount)
    }

    func testEmptyBookURLIsCountedButExistingBaseURLFallbackIsPreserved() async throws {
        var diagnostic = SearchDiagnostic()
        let html = "<article class='item'><h1>Invented title</h1></article>"
        let response = response(html)
        let books = try await BookSourceSearchRuntime(httpClient: MockHTTPClient(response: response))
            .search(source: source(), keyword: "x", diagnostic: &diagnostic)
        XCTAssertEqual(books.first?.bookURL, response.finalURL.absoluteString)
        XCTAssertEqual(diagnostic.missingBookURLCount, 1)
        XCTAssertEqual(diagnostic.filteredItemCount, 0)
        XCTAssertEqual(diagnostic.finalResultCount, 1)
    }

    func testBookListRuleFailureDoesNotInventAZeroMatchCount() async throws {
        var source = source()
        source.ruleSearch?.bookList = "@js:private-rule"
        let report = await BookSourceCompatibilityRunner(httpClient: MockHTTPClient(response: response(detail)))
            .run(sourceJSON: try JSONEncoder().encode(source), keyword: "x")
        let diagnostic = try XCTUnwrap(report.searchDiagnostic)
        XCTAssertEqual(diagnostic.lastStage, .bookList)
        XCTAssertEqual(diagnostic.ruleThrew, true)
        XCTAssertEqual(diagnostic.ruleFailureCategory, .unsupportedCapability)
        XCTAssertNil(diagnostic.bookListMatchedCount)
        XCTAssertNil(diagnostic.finalResultCount)
        XCTAssertNil(diagnostic.indexInRange)
        // Legacy array remains empty, which alone cannot distinguish this from zero matches.
        XCTAssertEqual(report.searchResults.count, 0)
    }

    func testRequiredFieldFailureKeepsListCountButLeavesFinalCountsUnknown() async throws {
        var source = source()
        source.ruleSearch?.name = "@js:private-rule"
        let report = await BookSourceCompatibilityRunner(
            httpClient: MockHTTPClient(response: response(detail)),
            javaScriptExecutor: DiagnosticThrowingJavaScript()
        ).run(sourceJSON: try JSONEncoder().encode(source), keyword: "x")
        let diagnostic = try XCTUnwrap(report.searchDiagnostic)
        XCTAssertEqual(diagnostic.lastStage, .fields)
        XCTAssertEqual(diagnostic.lastField, .name)
        XCTAssertEqual(diagnostic.bookListMatchedCount, 1)
        XCTAssertEqual(diagnostic.ruleThrew, true)
        XCTAssertEqual(diagnostic.ruleFailureCategory, .unknown)
        XCTAssertNil(diagnostic.finalResultCount)
        XCTAssertNil(diagnostic.missingNameCount)
        XCTAssertNil(diagnostic.filteredItemCount)
        XCTAssertNil(diagnostic.indexInRange)
    }

    func testOptionalRuleErrorRemainsNonfatalAndIsObserved() async throws {
        var source = source()
        source.ruleSearch?.intro = "@js:private-rule"
        var diagnostic = SearchDiagnostic()
        let books = try await BookSourceSearchRuntime(
            httpClient: MockHTTPClient(response: response(detail)),
            javaScriptExecutor: DiagnosticThrowingJavaScript()
        ).search(source: source, keyword: "x", diagnostic: &diagnostic)
        XCTAssertEqual(books.count, 1)
        XCTAssertNil(books.first?.intro)
        XCTAssertEqual(diagnostic.ruleThrew, true)
        XCTAssertEqual(diagnostic.finalResultCount, 1)
    }

    func testNonemptyResultIndexOutOfRangeDoesNotFetchBookInfo() async throws {
        let client = MockHTTPClient(response: response(detail))
        let report = await BookSourceCompatibilityRunner(httpClient: client)
            .run(sourceJSON: try JSONEncoder().encode(source()), keyword: "x", bookIndex: 1)
        XCTAssertEqual(report.searchResults.count, 1)
        XCTAssertEqual(report.searchDiagnostic?.finalResultCount, 1)
        XCTAssertEqual(report.searchDiagnostic?.requestedBookIndex, 1)
        XCTAssertEqual(report.searchDiagnostic?.indexInRange, false)
        XCTAssertNil(report.selectedSearchResult)
        let requests = await client.requests
        XCTAssertEqual(requests.count, 1)
    }

    func testRequestAndDecodeFailuresLeaveUnexecutedCountsNil() async throws {
        let data = try JSONEncoder().encode(source())
        let network = await BookSourceCompatibilityRunner(
            httpClient: MockHTTPClient(error: .transportError("private-error"))
        ).run(sourceJSON: data, keyword: "x")
        XCTAssertEqual(network.searchDiagnostic?.lastStage, .request)
        XCTAssertNil(network.searchDiagnostic?.responseStatusCode)
        XCTAssertNil(network.searchDiagnostic?.bookListMatchedCount)
        XCTAssertNil(network.searchDiagnostic?.ruleThrew)
        let decode = await BookSourceCompatibilityRunner(
            httpClient: MockHTTPClient(response: response(detail)), textDecoder: DiagnosticFailingDecoder()
        ).run(sourceJSON: data, keyword: "x")
        XCTAssertEqual(decode.failure?.stage, .charset)
        XCTAssertEqual(decode.searchDiagnostic?.lastStage, .responseDecode)
        XCTAssertEqual(decode.searchDiagnostic?.responseStatusCode, 200)
        XCTAssertNil(decode.searchDiagnostic?.finalResultCount)
        let encoded = try JSONEncoder().encode(try XCTUnwrap(decode.searchDiagnostic))
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        XCTAssertTrue(object["finalResultCount"] is NSNull)
        XCTAssertTrue(object["bookListMatchedCount"] is NSNull)
    }

    func testConstructionAndRuleSyntaxFailuresHaveDistinctBoundaries() async throws {
        var invalidRequest = source()
        invalidRequest.searchUrl = #"https://fixture.invalid/search?q={{key}},{"charset":"private-unsupported-charset"}"#
        let client = MockHTTPClient(response: response(detail))
        let construction = await BookSourceCompatibilityRunner(httpClient: client)
            .run(sourceJSON: try JSONEncoder().encode(invalidRequest), keyword: "x")
        XCTAssertEqual(construction.searchDiagnostic?.lastStage, .requestBuild)
        XCTAssertNil(construction.searchDiagnostic?.ruleThrew)
        XCTAssertNil(construction.searchDiagnostic?.responseByteCount)
        let requests = await client.requests
        XCTAssertTrue(requests.isEmpty)

        var invalidRule = source()
        invalidRule.ruleSearch?.bookList = "$[?(@.name"
        let syntax = await BookSourceCompatibilityRunner(httpClient: MockHTTPClient(response: response(detail)))
            .run(sourceJSON: try JSONEncoder().encode(invalidRule), keyword: "x")
        XCTAssertEqual(syntax.searchDiagnostic?.lastStage, .bookList)
        XCTAssertEqual(syntax.searchDiagnostic?.ruleFailureCategory, .ruleParser)
        XCTAssertNil(syntax.searchDiagnostic?.bookListMatchedCount)
    }

    func testPageHintsRequireStructuralEvidenceAndRemainAdvisory() {
        XCTAssertEqual(SearchPageHint.classify("<form action='?action=login'><input name='q'></form>"), .unknown)
        let login = "<form><input name='username'><input type='password'></form>"
        XCTAssertEqual(SearchPageHint.classify(login), .loginOrVerification)
        XCTAssertEqual(SearchPageHint.classify(login + "<form role='search'></form>"), .unknown)
        XCTAssertEqual(SearchPageHint.classify(String(repeating: "x", count: 262_145)), .unknown)
        var diagnostic = SearchDiagnostic()
        diagnostic.recordResponse(HTTPResponse(statusCode: 200,
            headers: HTTPHeaders(["Content-Type": "private-type; token=private-token"]),
            data: Data(), finalURL: URL(string: "https://fixture.invalid")!))
        XCTAssertEqual(diagnostic.responseContentType, .other)
    }

    private func source() -> BookSource {
        BookSource(bookSourceUrl: "https://fixture.invalid", bookSourceName: "Synthetic",
            searchUrl: "/search?q={{key}}",
            ruleSearch: SearchRule(bookList: "class.item", name: "tag.h1@text", bookUrl: "tag.a@href"))
    }

    private func response(_ html: String, redirected: Bool = false) -> HTTPResponse {
        let url = URL(string: "https://fixture.invalid/book/1?token=private-token")!
        return HTTPResponse(statusCode: 200,
            headers: HTTPHeaders(["Content-Type": "Text/HTML; charset=utf-8", "Set-Cookie": "private-cookie"]),
            data: Data(html.utf8), finalURL: url,
            redirects: redirected ? [HTTPRedirect(from: URL(string: "https://fixture.invalid/search")!,
                to: url, statusCode: 302)] : [])
    }
}

private struct DiagnosticPrivateError: Error {}
private struct DiagnosticThrowingJavaScript: RuleJavaScriptExecutor {
    func execute(script: String, context: JavaScriptExecutionContext) throws -> JavaScriptExecutionResult {
        throw DiagnosticPrivateError()
    }
}
private struct DiagnosticFailingDecoder: TextDecoder {
    func decode(_ data: Data, charset: String) throws -> String { throw DiagnosticPrivateError() }
}
