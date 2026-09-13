import Foundation
import XCTest
@testable import LegadoCompatibilityCLI
import LegadoCore

final class DiagnosticRequestCaptureTests: XCTestCase {
    func testCapturesBuilderBytesBeforeFailureAndOnlyFirstRequest() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let request = try await RequestBuilder().build(
            #"https://fixture.invalid/search,{"method":"POST","body":"searchkey={{key}}"}"#,
            context: RequestBuildContext(keyword: "苟在两界修仙"))
        let transport = MockHTTPClient(error: .transportError("private-error"))
        let capture = DiagnosticRequestCapture(transport: transport, directory: directory)
        do { _ = try await capture.send(request); XCTFail("Expected transport failure") } catch { }
        let bytes = try Data(contentsOf: directory.appendingPathComponent("request.body"))
        XCTAssertEqual(bytes, request.body)
        let snapshot = try JSONDecoder().decode(DiagnosticRequestSnapshot.self,
            from: Data(contentsOf: directory.appendingPathComponent("request.json")))
        XCTAssertEqual(snapshot.url, request.url.absoluteString)
        XCTAssertEqual(snapshot.method, "POST")
        XCTAssertEqual(snapshot.headers["Content-Type"], request.headers["Content-Type"])
        let later = HTTPRequest(url: URL(string: "https://fixture.invalid/later")!, body: Data([0, 255, 13, 10]))
        do { _ = try await capture.send(later) } catch { }
        XCTAssertEqual(try Data(contentsOf: directory.appendingPathComponent("request.body")), bytes)
        let sent = await transport.requests
        XCTAssertEqual(sent, [request, later])
    }

    func testReplayParsesSearchWithoutUsingNetworkOrFetchingOtherStages() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = #"{"bookSourceUrl":"https://fixture.invalid","bookSourceName":"Fixture","searchUrl":"/search?key={{key}}","ruleSearch":{"bookList":"class.book","name":"class.name@text","bookUrl":"class.name@href"}}"#
        let sourceURL = directory.appendingPathComponent("source.json")
        try Data(source.utf8).write(to: sourceURL)
        try Data(#"{"http_code":200,"url_effective":"https://fixture.invalid/results?private-token","num_redirects":1,"content_type":"text/html; charset=utf-8"}"#.utf8)
            .write(to: directory.appendingPathComponent("curl.stdout"))
        try Data(#"<div class="book"><a class="name" href="/book">虚构书名</a></div>"#.utf8)
            .write(to: directory.appendingPathComponent("curl.body"))
        let network = MockHTTPClient(error: .transportError("must never execute"))
        let execution = await CompatibilityCLIApplication().run(
            arguments: ["--source", sourceURL.path, "--keyword", "合成", "--json"],
            httpClient: network, replayDirectory: directory)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(execution.output.utf8)) as? [String: Any])
        let diagnostic = try XCTUnwrap(json["searchDiagnostic"] as? [String: Any])
        XCTAssertEqual(execution.exitCode, .success)
        XCTAssertEqual(diagnostic["finalResultCount"] as? Int, 1)
        XCTAssertEqual(diagnostic["responseRedirected"] as? Bool, true)
        XCTAssertFalse(execution.output.contains("private-token"))
        XCTAssertFalse(execution.output.contains("虚构书名"))
        let requests = await network.requests
        XCTAssertTrue(requests.isEmpty)
    }
}
