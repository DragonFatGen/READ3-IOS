import Foundation
import XCTest
@testable import LegadoCore

final class RequestBuilderTests: XCTestCase {
    func testPlainGETAndQuery() async throws {
        let request = try await RequestBuilder().build("https://example.invalid/search?q=swift")
        XCTAssertEqual(request.method, .get)
        XCTAssertEqual(request.url.absoluteString, "https://example.invalid/search?q=swift")
        XCTAssertNil(request.body)
    }

    func testGETQueryUsesFormSpacesWithoutDoubleEncodingPercentEscapes() async throws {
        let request = try await RequestBuilder().build(
            "https://example.invalid/search?hello world=hello world&path=%2Fbook%26part&term=阅读"
        )
        XCTAssertEqual(
            request.url.absoluteString,
            "https://example.invalid/search?hello+world=hello+world&path=%2Fbook%26part&term=%E9%98%85%E8%AF%BB"
        )
    }

    func testGETQueryPreservesOriginallyDoubleEncodedEscapeAndEncodesStrayPercent() async throws {
        let request = try await RequestBuilder().build(
            "https://example.invalid/search?literal=%252F&stray=%"
        )
        XCTAssertEqual(
            request.url.absoluteString,
            "https://example.invalid/search?literal=%252F&stray=%25"
        )
    }

    func testChineseGETQueryUsesConfiguredGBKCharset() async throws {
        let request = try await RequestBuilder().build(
            #"https://example.invalid/search?keyword=科幻,{"charset":"GBK"}"#
        )
        XCTAssertEqual(
            request.url.absoluteString,
            "https://example.invalid/search?keyword=%BF%C6%BB%C3"
        )
    }

    func testURLCharsetAliasEncodesEveryGETValueIncludingExistingEscape() async throws {
        let request = try await RequestBuilder().build(
            #"https://example.invalid/search?keyword=中文&escaped=%2F,{"charset":"cp936"}"#
        )
        XCTAssertEqual(
            request.url.absoluteString,
            "https://example.invalid/search?keyword=%D6%D0%CE%C4&escaped=%252F"
        )
    }

    func testChinesePOSTFormBodyUsesConfiguredGB18030Charset() async throws {
        let request = try await RequestBuilder().build(
            #"https://example.invalid/search,{"method":"POST","charset":"GB18030","body":"keyword=阅读"}"#
        )
        XCTAssertEqual(request.method, .post)
        XCTAssertEqual(request.bodyKind, .form)
        XCTAssertEqual(
            String(decoding: try XCTUnwrap(request.body), as: UTF8.self),
            "keyword=%D4%C4%B6%C1"
        )
    }

    func testRawPOSTUsesContentTypeCharsetInsteadOfURLOptionCharset() async throws {
        let request = try await RequestBuilder().build(
            #"https://example.invalid/raw,{"method":"POST","charset":"UTF-8","headers":{"Content-Type":"text/plain; charset=GBK"},"body":"中文"}"#
        )
        XCTAssertEqual(request.body, Data([0xD6, 0xD0, 0xCE, 0xC4]))
        XCTAssertEqual(request.bodyKind, .raw)
    }

    func testRawPOSTEncodingFailureIsTyped() async {
        await XCTAssertThrowsErrorAsync {
            _ = try await RequestBuilder().build(
                #"https://example.invalid/raw,{"method":"POST","headers":{"Content-Type":"text/plain; charset=GBK"},"body":"😀"}"#
            )
        } verify: {
            XCTAssertEqual($0 as? HTTPError, .encodingFailed("GBK"))
        }
    }

    func testURLBoundaryAndPOSTRawBody() async throws {
        let rule = #"https://example.invalid/api,{"method":"POST","body":{"name":"book"}}"#
        let request = try await RequestBuilder().build(rule)
        XCTAssertEqual(request.method, .post)
        XCTAssertEqual(request.bodyKind, .raw)
        XCTAssertEqual(String(decoding: try XCTUnwrap(request.body), as: UTF8.self), #"{"name":"book"}"#)
        XCTAssertEqual(request.headers["Content-Type"], "application/json; charset=UTF-8")
    }

    func testPOSTFormAndExplicitRawContentType() async throws {
        let form = try await RequestBuilder().build(
            #"https://example.invalid/form,{"method":"POST","body":"q=hello world&n=2"}"#
        )
        XCTAssertEqual(form.bodyKind, .form)
        XCTAssertEqual(String(decoding: try XCTUnwrap(form.body), as: UTF8.self), "q=hello+world&n=2")
        XCTAssertEqual(form.headers["content-type"], "application/x-www-form-urlencoded")

        let raw = try await RequestBuilder().build(
            #"https://example.invalid/raw,{"method":"POST","charset":"GBK","headers":{"Content-Type":"text/plain; charset=utf-8"},"body":"raw body"}"#
        )
        XCTAssertEqual(raw.bodyKind, .raw)
        XCTAssertEqual(raw.charset, "GBK")
        XCTAssertEqual(raw.headers["content-type"], "text/plain; charset=utf-8")
        XCTAssertEqual(String(decoding: try XCTUnwrap(raw.body), as: UTF8.self), "raw body")
    }

    func testHeaderUserAgentAndCaseInsensitiveRequestOverride() async throws {
        let request = try await RequestBuilder().build(
            #"https://example.invalid,{"headers":{"user-agent":"Request Agent","X-Mode":"request"}}"#,
            sourceHeader: #"{"User-Agent":"Source Agent","x-mode":"source","X-Source":"yes"}"#,
            context: RequestBuildContext(defaultUserAgent: "Default Agent")
        )
        XCTAssertEqual(request.headers["USER-AGENT"], "Request Agent")
        XCTAssertEqual(request.headers["x-mode"], "request")
        XCTAssertEqual(request.headers["X-Source"], "yes")
    }

    func testOptionStringHeadersRetryAndDeferredCapabilities() async throws {
        let rule = #"https://example.invalid,{"headers":"{\"X-Test\":\"ok\"}","retry":2,"charset":"GBK","proxy":"http://localhost:8080","webView":true,"webJs":"run()","js":"url"}"#
        let request = try await RequestBuilder().build(rule)
        XCTAssertEqual(request.headers["X-Test"], "ok")
        XCTAssertEqual(request.retryCount, 2)
        XCTAssertEqual(request.charset, "GBK")
        XCTAssertEqual(request.options.proxy, "http://localhost:8080")
        XCTAssertTrue(request.options.requiresWebView)
        XCTAssertTrue(request.options.requiresJavaScript)
    }

    func testMalformedOptionsCompatibleAndStrict() async throws {
        let malformed = "https://example.invalid,{bad}"
        let compatible = try await RequestBuilder().build(malformed)
        XCTAssertEqual(compatible.url.absoluteString, "https://example.invalid")
        await XCTAssertThrowsErrorAsync {
            _ = try await RequestBuilder().build(
                malformed,
                context: RequestBuildContext(errorPolicy: .strict)
            )
        }
    }

    func testKeywordPagePageSizeSourceURLBaseURLAndSourceVariableTemplates() async throws {
        let context = RequestBuildContext(
            keyword: "swift",
            page: 3,
            pageSize: 20,
            sourceURL: "source-id",
            baseURL: "https://example.invalid/root/",
            sourceVariables: ["token": "abc"]
        )
        let request = try await RequestBuilder().build(
            "search/{{keyword}}/{{page}}/{{pageSize}}/{{token}}?source={{sourceUrl}}",
            context: context
        )
        XCTAssertEqual(
            request.url.absoluteString,
            "https://example.invalid/root/search/swift/3/20/abc?source=source-id"
        )
    }

    func testAndroidPageAlternativeSyntax() async throws {
        let request = try await RequestBuilder().build(
            "https://example.invalid/<first,second,last>",
            context: RequestBuildContext(page: 5)
        )
        XCTAssertEqual(request.url.absoluteString, "https://example.invalid/last")
    }

    func testExistingGetPutTemplateMechanismAndBookSourceEntryPoint() async throws {
        let source = BookSource(
            bookSourceUrl: "https://example.invalid/base/",
            header: #"{"X-Source":"yes","proxy":"socks5://localhost:1080"}"#
        )
        let request = try await RequestBuilder().build(
            #"next/@put:{"saved":"@get:{keyword}"}@get:{saved}"#,
            source: source,
            context: RequestBuildContext(keyword: "book")
        )
        XCTAssertEqual(request.url.absoluteString, "https://example.invalid/base/next/book")
        XCTAssertEqual(request.headers["X-Source"], "yes")
        XCTAssertNil(request.headers["proxy"])
        XCTAssertEqual(request.options.proxy, "socks5://localhost:1080")
    }

    func testUnsupportedMethodStrictAndCompatibleFallback() async throws {
        let rule = #"https://example.invalid,{"method":"PUT"}"#
        let compatible = try await RequestBuilder().build(rule)
        XCTAssertEqual(compatible.method, .get)
        await XCTAssertThrowsErrorAsync {
            _ = try await RequestBuilder().build(rule, context: RequestBuildContext(errorPolicy: .strict))
        }
    }

    func testCookieMergeRequestCookieWins() async throws {
        let store = InMemoryHTTPCookieStore()
        let url = try XCTUnwrap(URL(string: "https://books.example.invalid/path"))
        try await store.store([
            LegadoCore.HTTPCookie(name: "session", value: "stored", domain: "books.example.invalid"),
            LegadoCore.HTTPCookie(name: "theme", value: "dark", domain: "books.example.invalid")
        ], for: url, sourceIdentifier: "source-a")
        let request = try await RequestBuilder(cookieStore: store).build(
            #"https://books.example.invalid/path,{"headers":{"Cookie":"session=request"}}"#,
            context: RequestBuildContext(sourceIdentifier: "source-a")
        )
        XCTAssertEqual(request.headers["Cookie"], "session=request; theme=dark")
        XCTAssertEqual(request.cookies.count, 2)
    }

    func testCookieStoreIsSharedAcrossSourcesForSameDomain() async throws {
        let store = InMemoryHTTPCookieStore()
        let url = try XCTUnwrap(URL(string: "https://example.invalid/"))
        try await store.store(
            [LegadoCore.HTTPCookie(name: "id", value: "one", domain: "example.invalid")],
            for: url,
            sourceIdentifier: "one"
        )
        let sourceOne = try await store.cookies(for: url, sourceIdentifier: "one")
        let sourceTwo = try await store.cookies(for: url, sourceIdentifier: "two")
        XCTAssertEqual(sourceOne.map(\.value), ["one"])
        XCTAssertEqual(sourceTwo.map(\.value), ["one"])
    }

    func testDeterministicBuildAndContextIsolation() async throws {
        let builder = RequestBuilder()
        let firstContext = RequestBuildContext(keyword: "one", sourceVariables: ["token": "a"])
        let secondContext = RequestBuildContext(keyword: "two", sourceVariables: ["token": "b"])
        let first = try await builder.build("https://example.invalid/{{keyword}}/{{token}}", context: firstContext)
        let repeated = try await builder.build("https://example.invalid/{{keyword}}/{{token}}", context: firstContext)
        XCTAssertEqual(first, repeated)
        let second = try await builder.build("https://example.invalid/{{keyword}}/{{token}}", context: secondContext)
        XCTAssertEqual(first.url.absoluteString, "https://example.invalid/one/a")
        XCTAssertEqual(second.url.absoluteString, "https://example.invalid/two/b")
    }

    func testConcurrentIndependentRequests() async throws {
        let builder = RequestBuilder()
        let requests = try await withThrowingTaskGroup(of: HTTPRequest.self) { group in
            for page in 1...8 {
                group.addTask {
                    try await builder.build(
                        "https://example.invalid/{{page}}",
                        context: RequestBuildContext(page: page)
                    )
                }
            }
            var values: [HTTPRequest] = []
            for try await request in group { values.append(request) }
            return values
        }
        XCTAssertEqual(Set(requests.map(\.url.absoluteString)).count, 8)
    }
}

private func XCTAssertThrowsErrorAsync(
    _ expression: () async throws -> Void,
    verify: ((any Error) -> Void)? = nil,
    file: StaticString = #filePath,
    line: UInt = #line
) async {
    do {
        try await expression()
        XCTFail("Expected error", file: file, line: line)
    } catch {
        verify?(error)
    }
}
