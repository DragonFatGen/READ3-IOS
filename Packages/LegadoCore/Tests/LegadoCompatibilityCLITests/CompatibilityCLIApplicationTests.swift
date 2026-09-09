import Foundation
import XCTest
@testable import LegadoCompatibilityCLI
@testable import LegadoCore

final class CompatibilityCLIApplicationTests: XCTestCase {
    func testInvalidSourceShapeReturnsInputExitCodeWithoutRequests() async throws {
        let file = try temporarySourceFile(data: Data("[]".utf8))
        defer { try? FileManager.default.removeItem(at: file) }
        let client = MockHTTPClient(error: .transportError("must not execute"))
        let execution = await CompatibilityCLIApplication().run(
            arguments: ["--source", file.path, "--keyword", "书", "--json"],
            httpClient: client
        )
        XCTAssertEqual(execution.exitCode, .inputError)
        let report = try JSONDecoder().decode(CompatibilityReportDTO.self, from: Data(execution.output.utf8))
        XCTAssertEqual(report.failureOperation, "import")
        let requests = await client.requests
        XCTAssertTrue(requests.isEmpty)
    }

    func testArgumentErrorsDoNotEchoUntrustedValues() async {
        for arguments in [["--token=private-value"], ["--book-index", "private-value"]] {
            let execution = await CompatibilityCLIApplication().run(
                arguments: arguments,
                httpClient: MockHTTPClient(error: .transportError("must not execute"))
            )
            XCTAssertEqual(execution.exitCode, .inputError)
            XCTAssertFalse(execution.output.contains("private-value"))
        }
    }

    func testBothReportFormatsRedactMultipartCredentials() async throws {
        let file = try temporarySourceFile(data: try fixture("chinese-source.json"))
        defer { try? FileManager.default.removeItem(at: file) }
        for format in [[], ["--json"]] {
            let execution = await CompatibilityCLIApplication().run(
                arguments: ["--source", file.path, "--keyword", "书"] + format,
                httpClient: MockHTTPClient(error: .transportError(
                    "Authorization: Bearer private-auth\nCookie: a=private-cookie; b=private-second\n"
                    + "\"password\": \"private-password\"\nloginParams=private-login\nvariables=private-variable"
                ))
            )
            XCTAssertEqual(execution.exitCode, .compatibilityFailure)
            XCTAssertFalse(execution.output.contains("private-"))
            XCTAssertTrue(execution.output.contains("<redacted>"))
        }
    }

    func testMissingSourceFileReturnsInputExitCode() async {
        let missing = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("json")
        let execution = await CompatibilityCLIApplication().run(
            arguments: ["--source", missing.path, "--keyword", "三体"],
            httpClient: MockHTTPClient(error: .transportError("must not execute"))
        )
        XCTAssertEqual(execution.exitCode, .inputError)
        XCTAssertTrue(execution.output.contains("Unable to read"))
    }

    func testInvalidJSONReturnsInputExitCode() async throws {
        let file = try temporarySourceFile(data: Data("not-json".utf8))
        defer { try? FileManager.default.removeItem(at: file) }
        let execution = await CompatibilityCLIApplication().run(
            arguments: ["--source", file.path, "--keyword", "三体", "--json"],
            httpClient: MockHTTPClient(error: .transportError("must not execute"))
        )
        XCTAssertEqual(execution.exitCode, .inputError)
        let report = try JSONDecoder().decode(CompatibilityReportDTO.self, from: Data(execution.output.utf8))
        XCTAssertEqual(report.failureCategory, "input")
    }

    func testSuccessfulRunRendersHumanReadableSummaryWithoutContent() async throws {
        let file = try temporarySourceFile(data: try fixture("chinese-source.json"))
        defer { try? FileManager.default.removeItem(at: file) }
        let execution = await CompatibilityCLIApplication().run(
            arguments: ["--source", file.path, "--keyword", "科幻"],
            httpClient: MockHTTPClient(results: try successfulResponses())
        )
        XCTAssertEqual(execution.exitCode, .success)
        XCTAssertTrue(execution.output.contains("Overall: SUCCESS"))
        XCTAssertTrue(execution.output.contains("Completed stage: content"))
        XCTAssertTrue(execution.output.contains("Selected book: 三体"))
        XCTAssertTrue(execution.output.contains("Selected author: 刘慈欣"))
        XCTAssertTrue(execution.output.contains("Selected chapter: 第一章 科学边界"))
        XCTAssertTrue(execution.output.contains("Content characters: 10"))
        XCTAssertFalse(execution.output.contains("宇宙很大"))
    }

    func testSuccessfulRunRendersCodableJSONSummary() async throws {
        let file = try temporarySourceFile(data: try fixture("chinese-source.json"))
        defer { try? FileManager.default.removeItem(at: file) }
        let execution = await CompatibilityCLIApplication().run(
            arguments: ["--source", file.path, "--keyword", "科幻", "--json"],
            httpClient: MockHTTPClient(results: try successfulResponses())
        )
        XCTAssertEqual(execution.exitCode, .success)
        let report = try JSONDecoder().decode(CompatibilityReportDTO.self, from: Data(execution.output.utf8))
        XCTAssertTrue(report.successful)
        XCTAssertEqual(report.completedStage, "content")
        XCTAssertEqual(report.searchResultCount, 1)
        XCTAssertEqual(report.chapterCount, 1)
        XCTAssertEqual(report.contentCharacterCount, 10)
        XCTAssertFalse(execution.output.contains("宇宙很大"))
        XCTAssertFalse(execution.output.contains("bookSourceUrl"))
    }

    func testPartialRunReturnsCompatibilityFailureAndLastCompletedStage() async throws {
        let file = try temporarySourceFile(data: try fixture("chinese-source.json"))
        defer { try? FileManager.default.removeItem(at: file) }
        let search = try response("search.html", url: "https://fixture.invalid/search")
        let execution = await CompatibilityCLIApplication().run(
            arguments: ["--source", file.path, "--keyword", "科幻", "--json"],
            httpClient: MockHTTPClient(results: [
                .success(search),
                .failure(.transportError("offline"))
            ])
        )
        XCTAssertEqual(execution.exitCode, .compatibilityFailure)
        let report = try JSONDecoder().decode(CompatibilityReportDTO.self, from: Data(execution.output.utf8))
        XCTAssertEqual(report.completedStage, "search")
        XCTAssertEqual(report.selectedBookName, "三体")
        XCTAssertEqual(report.failureCategory, "request")
        XCTAssertEqual(report.failureOperation, "bookInfo")
    }

    func testFailureOutputRetainsRunnerRedaction() async throws {
        let file = try temporarySourceFile(data: try fixture("chinese-source.json"))
        defer { try? FileManager.default.removeItem(at: file) }
        let execution = await CompatibilityCLIApplication().run(
            arguments: ["--source", file.path, "--keyword", "科幻"],
            httpClient: MockHTTPClient(error: .transportError(
                "Authorization=private-auth Cookie=private-cookie token=private-token"
            ))
        )
        XCTAssertEqual(execution.exitCode, .compatibilityFailure)
        XCTAssertTrue(execution.output.contains("<redacted>"))
        XCTAssertFalse(execution.output.contains("private-auth"))
        XCTAssertFalse(execution.output.contains("private-cookie"))
        XCTAssertFalse(execution.output.contains("private-token"))
    }

    func testArgumentFailureReturnsInputExitCodeAndHelp() async {
        let execution = await CompatibilityCLIApplication().run(
            arguments: ["--keyword", "三体"],
            httpClient: MockHTTPClient(error: .transportError("must not execute"))
        )
        XCTAssertEqual(execution.exitCode, .inputError)
        XCTAssertTrue(execution.output.contains("--source"))
        XCTAssertTrue(execution.output.contains("Usage:"))
    }

    private func successfulResponses() throws -> [Result<HTTPResponse, HTTPError>] {
        [
            .success(try response("search.html", url: "https://fixture.invalid/search")),
            .success(try response("book-info.html", url: "https://fixture.invalid/book/three")),
            .success(try response("toc.html", url: "https://fixture.invalid/book/three/chapters")),
            .success(try response("content.html", url: "https://fixture.invalid/book/three/chapter/1"))
        ]
    }

    private func response(_ name: String, url: String) throws -> HTTPResponse {
        HTTPResponse(
            statusCode: 200,
            headers: HTTPHeaders(["Content-Type": "text/html; charset=UTF-8"]),
            data: try fixture(name),
            finalURL: try XCTUnwrap(URL(string: url))
        )
    }

    private func fixture(_ name: String) throws -> Data {
        try Data(contentsOf: repositoryRoot
            .appendingPathComponent("TestSources")
            .appendingPathComponent("compatibility")
            .appendingPathComponent(name))
    }

    private func temporarySourceFile(data: Data) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("json")
        try data.write(to: url, options: .atomic)
        return url
    }

    private var repositoryRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}
