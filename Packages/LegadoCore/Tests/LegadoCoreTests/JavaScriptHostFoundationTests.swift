import Foundation
import XCTest
@testable import LegadoCore

final class JavaScriptHostFoundationTests: XCTestCase {
    func testDefaultLimitsAreDocumentedValues() {
        XCTAssertEqual(JavaScriptHostLimits.default.maximumNetworkRequestsPerExecution, 16)
        XCTAssertEqual(JavaScriptHostLimits.default.maximumRequestBodyBytes, 1_048_576)
        XCTAssertEqual(JavaScriptHostLimits.default.maximumResponseBodyBytes, 8_388_608)
    }

    func testNegativeLimitsNormalizeToZero() {
        let limits = JavaScriptHostLimits(
            maximumNetworkRequestsPerExecution: -1,
            maximumRequestBodyBytes: -2,
            maximumResponseBodyBytes: -3
        )
        XCTAssertEqual(limits, JavaScriptHostLimits(
            maximumNetworkRequestsPerExecution: 0,
            maximumRequestBodyBytes: 0,
            maximumResponseBodyBytes: 0
        ))
    }

    func testBudgetRecordsEveryStartedRequest() throws {
        var budget = JavaScriptHostBudget(limits: .init(maximumNetworkRequestsPerExecution: 2))
        try budget.beginRequest()
        try budget.beginRequest()
        XCTAssertEqual(budget.networkRequestCount, 2)
    }

    func testBudgetRejectsRequestBeyondLimit() throws {
        var budget = JavaScriptHostBudget(limits: .init(maximumNetworkRequestsPerExecution: 1))
        try budget.beginRequest()
        XCTAssertThrowsError(try budget.beginRequest()) {
            XCTAssertEqual($0 as? JavaScriptHostError, .requestLimitExceeded(maximum: 1))
        }
    }

    func testZeroRequestBudgetRejectsFirstCall() {
        var budget = JavaScriptHostBudget(limits: .init(maximumNetworkRequestsPerExecution: 0))
        XCTAssertThrowsError(try budget.beginRequest()) {
            XCTAssertEqual($0 as? JavaScriptHostError, .requestLimitExceeded(maximum: 0))
        }
    }

    func testRequestBodyLimitUsesUTF8Bytes() {
        var budget = JavaScriptHostBudget(limits: .init(maximumRequestBodyBytes: 3))
        XCTAssertThrowsError(try budget.beginRequest(body: "阅读")) {
            XCTAssertEqual(
                $0 as? JavaScriptHostError,
                .requestBodyLimitExceeded(actual: 6, maximum: 3)
            )
        }
        XCTAssertEqual(budget.networkRequestCount, 0)
    }

    func testRequestBodyAtLimitIsAccepted() throws {
        var budget = JavaScriptHostBudget(limits: .init(maximumRequestBodyBytes: 3))
        try budget.beginRequest(body: "abc")
        XCTAssertEqual(budget.networkRequestCount, 1)
    }

    func testResponseBodyLimitUsesUTF8Bytes() {
        let response = makeResponse(body: "阅读")
        let budget = JavaScriptHostBudget(limits: .init(maximumResponseBodyBytes: 5))
        XCTAssertThrowsError(try budget.validate(response)) {
            XCTAssertEqual(
                $0 as? JavaScriptHostError,
                .responseBodyLimitExceeded(actual: 6, maximum: 5)
            )
        }
    }

    func testAjaxResponseBodyUsesSameLimit() {
        let budget = JavaScriptHostBudget(limits: .init(maximumResponseBodyBytes: 1))
        XCTAssertThrowsError(try budget.validateAjaxBody("ab")) {
            XCTAssertEqual(
                $0 as? JavaScriptHostError,
                .responseBodyLimitExceeded(actual: 2, maximum: 1)
            )
        }
    }

    func testNilAjaxBodyIsAllowed() throws {
        try JavaScriptHostBudget(limits: .init(maximumResponseBodyBytes: 0))
            .validateAjaxBody(nil)
    }

    func testBudgetsAreIndependentValues() throws {
        var first = JavaScriptHostBudget(limits: .init(maximumNetworkRequestsPerExecution: 1))
        var second = JavaScriptHostBudget(limits: .init(maximumNetworkRequestsPerExecution: 1))
        try first.beginRequest()
        try second.beginRequest()
        XCTAssertEqual(first.networkRequestCount, 1)
        XCTAssertEqual(second.networkRequestCount, 1)
    }

    func testResponseHeaderLookupIsCaseInsensitive() {
        let response = makeResponse(headers: ["Content-Type": "text/plain", "X-ID": "42"])
        XCTAssertEqual(response.header("content-type"), "text/plain")
        XCTAssertEqual(response.header("x-id"), "42")
        XCTAssertNil(response.header("missing"))
    }

    func testResponseCookieLookupIsExplicit() {
        let response = makeResponse(cookies: ["sid": "abc"])
        XCTAssertEqual(response.cookie("sid"), "abc")
        XCTAssertNil(response.cookie("missing"))
    }

    func testResponseSnapshotRoundTripsDeterministically() throws {
        let response = makeResponse(
            body: "payload",
            headers: ["B": "2", "A": "1"],
            cookies: ["sid": "abc"]
        )
        let data = try JSONEncoder().encode(response)
        XCTAssertEqual(try JSONDecoder().decode(JavaScriptHTTPResponseSnapshot.self, from: data), response)
    }

    func testAjaxHostCapturesURLAndContext() throws {
        let host = CapturingRuleJavaScriptHost()
        let context = makeContext()
        XCTAssertEqual(try host.ajax("https://example.invalid/ajax", context: context), "ajax-body")
        XCTAssertEqual(host.calls, [.ajax("https://example.invalid/ajax", context)])
    }

    func testGetHostCapturesHeaders() throws {
        let host = CapturingRuleJavaScriptHost()
        let context = makeContext()
        _ = try host.get("https://example.invalid/get", headers: ["X-Test": "one"], context: context)
        XCTAssertEqual(host.calls, [
            .get("https://example.invalid/get", ["X-Test": "one"], context)
        ])
    }

    func testPostHostCapturesBodyAndHeaders() throws {
        let host = CapturingRuleJavaScriptHost()
        let context = makeContext()
        _ = try host.post(
            "https://example.invalid/post",
            body: "a=1",
            headers: ["Content-Type": "application/x-www-form-urlencoded"],
            context: context
        )
        XCTAssertEqual(host.calls, [
            .post(
                "https://example.invalid/post",
                "a=1",
                ["Content-Type": "application/x-www-form-urlencoded"],
                context
            )
        ])
    }

    func testHeadHostCapturesHeaders() throws {
        let host = CapturingRuleJavaScriptHost()
        let context = makeContext()
        _ = try host.head("https://example.invalid/head", headers: ["Accept": "*/*"], context: context)
        XCTAssertEqual(host.calls, [
            .head("https://example.invalid/head", ["Accept": "*/*"], context)
        ])
    }

    func testAndroidAjaxFailuresAreClassifiedExplicitly() {
        XCTAssertTrue(JavaScriptHostError.networkUnavailable.isAndroidAjaxTextResult)
        XCTAssertTrue(JavaScriptHostError.invalidRequest("bad").isAndroidAjaxTextResult)
        XCTAssertTrue(JavaScriptHostError.transportFailed("offline").isAndroidAjaxTextResult)
        XCTAssertTrue(JavaScriptHostError.unsupportedCharset("gbk").isAndroidAjaxTextResult)
        XCTAssertTrue(JavaScriptHostError.timeout.isAndroidAjaxTextResult)
    }

    func testSafetyAndProgrammingErrorsStayExceptions() {
        XCTAssertFalse(JavaScriptHostError.requestLimitExceeded(maximum: 1).isAndroidAjaxTextResult)
        XCTAssertFalse(
            JavaScriptHostError.responseBodyLimitExceeded(actual: 2, maximum: 1)
                .isAndroidAjaxTextResult
        )
        XCTAssertFalse(JavaScriptHostError.cancelled.isAndroidAjaxTextResult)
        XCTAssertFalse(JavaScriptHostError.unsupportedHostMethod("put").isAndroidAjaxTextResult)
    }

    func testJavaScriptSourceSnapshotContainsOnlyMinimumRequestIdentity() {
        let source = JavaScriptSourceSnapshot(
            identifier: "source-id",
            url: "https://source.invalid",
            header: #"{"User-Agent":"Reader"}"#
        )
        XCTAssertEqual(source.identifier, "source-id")
        XCTAssertEqual(source.url, "https://source.invalid")
        XCTAssertEqual(source.header, #"{"User-Agent":"Reader"}"#)
    }

    func testRuleExecutorPassesSourceSnapshotToJavaScriptExecutor() throws {
        let source = JavaScriptSourceSnapshot(
            identifier: "source-id",
            url: "https://source.invalid",
            header: nil
        )
        let executor = SourceCapturingJavaScriptExecutor()
        var context = RuleExecutionContext(javaScriptSource: source)
        _ = try RuleExecutor(javaScriptExecutor: executor).execute(
            .javaScript("result"),
            input: RuleExecutionInput(.none),
            context: &context
        )
        XCTAssertEqual(executor.contexts.first?.source, source)
    }

    private func makeContext() -> JavaScriptExecutionContext {
        JavaScriptExecutionContext(
            result: .string("previous"),
            baseUrl: "https://base.invalid/path",
            source: JavaScriptSourceSnapshot(
                identifier: "source-id",
                url: "https://source.invalid",
                header: #"{"X-Source":"one"}"#
            ),
            sourceVariables: ["token": "source"],
            temporaryVariables: ["token": "temporary"]
        )
    }

    private func makeResponse(
        body: String = "body",
        headers: [String: String] = [:],
        cookies: [String: String] = [:]
    ) -> JavaScriptHTTPResponseSnapshot {
        JavaScriptHTTPResponseSnapshot(
            body: body,
            statusCode: 200,
            statusMessage: "OK",
            headers: headers,
            cookies: cookies,
            url: "https://example.invalid/final",
            contentType: "text/plain",
            charset: "UTF-8",
            method: .get
        )
    }
}

private enum CapturedHostCall: Equatable {
    case ajax(String, JavaScriptExecutionContext)
    case get(String, [String: String], JavaScriptExecutionContext)
    case post(String, String, [String: String], JavaScriptExecutionContext)
    case head(String, [String: String], JavaScriptExecutionContext)
}

/// Locking is confined to deterministic test capture state and makes this fake
/// satisfy the production protocol's Sendable requirement.
private final class CapturingRuleJavaScriptHost: RuleJavaScriptHost, @unchecked Sendable {
    private let lock = NSLock()
    private var capturedCalls: [CapturedHostCall] = []

    var calls: [CapturedHostCall] {
        lock.withLock { capturedCalls }
    }

    func ajax(_ url: String, context: JavaScriptExecutionContext) throws -> String? {
        lock.withLock { capturedCalls.append(.ajax(url, context)) }
        return "ajax-body"
    }

    func get(
        _ url: String,
        headers: [String: String],
        context: JavaScriptExecutionContext
    ) throws -> JavaScriptHTTPResponseSnapshot {
        lock.withLock { capturedCalls.append(.get(url, headers, context)) }
        return response(url: url, method: .get)
    }

    func post(
        _ url: String,
        body: String,
        headers: [String: String],
        context: JavaScriptExecutionContext
    ) throws -> JavaScriptHTTPResponseSnapshot {
        lock.withLock { capturedCalls.append(.post(url, body, headers, context)) }
        return response(url: url, method: .post)
    }

    func head(
        _ url: String,
        headers: [String: String],
        context: JavaScriptExecutionContext
    ) throws -> JavaScriptHTTPResponseSnapshot {
        lock.withLock { capturedCalls.append(.head(url, headers, context)) }
        return response(url: url, method: .head)
    }

    private func response(
        url: String,
        method: JavaScriptHTTPMethod
    ) -> JavaScriptHTTPResponseSnapshot {
        JavaScriptHTTPResponseSnapshot(
            body: "response",
            statusCode: 200,
            statusMessage: "OK",
            url: url,
            method: method
        )
    }
}

private final class SourceCapturingJavaScriptExecutor: RuleJavaScriptExecutor, @unchecked Sendable {
    private let lock = NSLock()
    private var capturedContexts: [JavaScriptExecutionContext] = []

    var contexts: [JavaScriptExecutionContext] {
        lock.withLock { capturedContexts }
    }

    func execute(
        script: String,
        context: JavaScriptExecutionContext
    ) throws -> JavaScriptExecutionResult {
        lock.withLock { capturedContexts.append(context) }
        return .undefined
    }
}
