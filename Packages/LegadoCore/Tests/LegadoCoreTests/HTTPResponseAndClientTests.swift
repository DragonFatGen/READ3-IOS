import Foundation
import XCTest
@testable import LegadoCore

final class HTTPResponseAndClientTests: XCTestCase {
    func testUTF8ResponseRawDataStatusAndFinalURL() throws {
        let data = Data("阅读三".utf8)
        let url = try XCTUnwrap(URL(string: "https://example.invalid/final"))
        let response = HTTPResponse(statusCode: 200, data: data, finalURL: url)
        XCTAssertEqual(try response.text(), "阅读三")
        XCTAssertEqual(response.data, data)
        XCTAssertEqual(response.statusCode, 200)
        XCTAssertEqual(response.finalURL, url)
    }

    func testContentTypeCharsetAndExplicitCharsetPriority() throws {
        let url = try XCTUnwrap(URL(string: "https://example.invalid"))
        let latin = try XCTUnwrap("café".data(using: .isoLatin1))
        let response = HTTPResponse(
            statusCode: 200,
            headers: HTTPHeaders(["Content-Type": "text/plain; charset=iso-8859-1"]),
            data: latin,
            finalURL: url
        )
        XCTAssertEqual(response.contentTypeCharset, "iso-8859-1")
        XCTAssertEqual(try response.text(), "café")
        XCTAssertThrowsError(try response.text(explicitCharset: "GBK")) {
            XCTAssertEqual($0 as? HTTPError, .unsupportedCharset("GBK"))
        }
    }

    func testRedirectAndCookieMetadata() throws {
        let from = try XCTUnwrap(URL(string: "http://example.invalid/start"))
        let final = try XCTUnwrap(URL(string: "https://example.invalid/final"))
        let cookie = HTTPCookie(
            name: "session",
            value: "value",
            domain: "example.invalid",
            isSecure: true,
            isHTTPOnly: true
        )
        let response = HTTPResponse(
            statusCode: 200,
            data: Data(),
            finalURL: final,
            redirects: [HTTPRedirect(from: from, to: final, statusCode: 301)],
            cookies: [cookie]
        )
        XCTAssertEqual(response.redirects.first?.statusCode, 301)
        XCTAssertEqual(response.cookies, [cookie])
        XCTAssertTrue(cookie.matches(final))
        XCTAssertFalse(cookie.matches(from))
    }

    func testMockClientCapturesRequestAndResponse() async throws {
        let url = try XCTUnwrap(URL(string: "https://example.invalid"))
        let response = HTTPResponse(statusCode: 204, data: Data(), finalURL: url)
        let client = MockHTTPClient(response: response)
        let request = HTTPRequest(url: url)
        let received = try await client.send(request)
        let requests = await client.requests
        XCTAssertEqual(received, response)
        XCTAssertEqual(requests, [request])
    }

    func testMockTransportError() async throws {
        let url = try XCTUnwrap(URL(string: "https://example.invalid"))
        let client = MockHTTPClient(error: .transportError("offline"))
        do {
            _ = try await client.send(HTTPRequest(url: url))
            XCTFail("Expected transport error")
        } catch {
            XCTAssertEqual(error as? HTTPError, .transportError("offline"))
        }
    }
}
