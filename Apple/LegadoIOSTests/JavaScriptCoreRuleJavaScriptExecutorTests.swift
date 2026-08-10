import LegadoCore
import XCTest
@testable import LegadoIOS

final class JavaScriptCoreRuleJavaScriptExecutorTests: XCTestCase {
    private let executor = JavaScriptCoreRuleJavaScriptExecutor()

    func testArithmetic() throws {
        XCTAssertEqual(try evaluate("1 + 2"), .number(3))
    }

    func testStringConcatenation() throws {
        XCTAssertEqual(try evaluate("'read' + '3'"), .string("read3"))
    }

    func testResultBindingReadsPreviousString() throws {
        XCTAssertEqual(try evaluate("result + '-next'", result: .string("chapter")), .string("chapter-next"))
    }

    func testResultBindingReadsPreviousArray() throws {
        XCTAssertEqual(
            try evaluate("result.join('|')", result: .strings(["a", "b"])),
            .string("a|b")
        )
    }

    func testBaseUrlBinding() throws {
        XCTAssertEqual(
            try evaluate("baseUrl + '/2'", baseUrl: "https://example.invalid/1"),
            .string("https://example.invalid/1/2")
        )
    }

    func testBooleanAndNumbers() throws {
        XCTAssertEqual(try evaluate("true"), .boolean(true))
        XCTAssertEqual(try evaluate("1"), .number(1))
        XCTAssertEqual(try evaluate("1.5"), .number(1.5))
    }

    func testNullAndUndefinedRemainDistinctAtAdapterBoundary() throws {
        XCTAssertEqual(try evaluate("null"), .null)
        XCTAssertEqual(try evaluate("undefined"), .undefined)
    }

    func testArrayMappingPreservesOrderAndTypes() throws {
        XCTAssertEqual(
            try evaluate("['a', 2, false, null, undefined]"),
            .array([.string("a"), .number(2), .boolean(false), .null, .undefined])
        )
    }

    func testObjectMappingIsPlatformNeutral() throws {
        XCTAssertEqual(
            try evaluate("({b: 2, a: 'one'})"),
            .object(["a": .string("one"), "b": .number(2)])
        )
    }

    func testSyntaxErrorIsTyped() {
        XCTAssertThrowsError(try evaluate("var =")) {
            guard let error = $0 as? JavaScriptExecutionError,
                  case .evaluationFailed = error else {
                return XCTFail("Expected JavaScript evaluation failure, got \($0)")
            }
        }
    }

    func testRuntimeErrorIsTyped() {
        XCTAssertThrowsError(try evaluate("missing.value")) {
            guard let error = $0 as? JavaScriptExecutionError,
                  case .evaluationFailed = error else {
                return XCTFail("Expected JavaScript evaluation failure, got \($0)")
            }
        }
    }

    func testJavaObjectIsAbsentWithoutInjectedHost() throws {
        XCTAssertEqual(try evaluate("typeof java"), .string("undefined"))
    }

    func testAjaxPassesFullLegadoURLStringToMockHost() throws {
        let executor = JavaScriptCoreRuleJavaScriptExecutor(host: ImmediateJavaScriptHost())
        XCTAssertEqual(
            try executor.execute(
                script: #"java.ajax('https://example.invalid/api,{"method":"POST","body":"a=1"}')"#,
                context: JavaScriptExecutionContext(result: .none, baseUrl: "")
            ),
            .string(#"ajax:https://example.invalid/api,{"method":"POST","body":"a=1"}"#)
        )
    }

    func testAjaxReceivesExecutionContextWithoutImplicitURLResolution() throws {
        let executor = JavaScriptCoreRuleJavaScriptExecutor(host: ImmediateJavaScriptHost())
        XCTAssertEqual(
            try executor.execute(
                script: "java.ajax('/relative')",
                context: JavaScriptExecutionContext(
                    result: .string("previous"),
                    baseUrl: "https://base.invalid/path"
                )
            ),
            .string("ajax:/relative")
        )
    }

    func testGetReturnsResponseReaderMethods() throws {
        let result = try hostEvaluate(#"""
        (function() {
            var r = java.get("https://example.invalid/get", {"X-Test":"one"});
            return [r.body(), r.statusCode(), r.statusMessage(), r.method(), r.url()];
        })()
        """#)
        XCTAssertEqual(result, .array([
            .string("GET:one"), .number(302), .string("Found"),
            .string("GET"), .string("https://example.invalid/get")
        ]))
    }

    func testResponseHeadersCookiesAndMetadataAreAllowlisted() throws {
        let result = try hostEvaluate(#"""
        (function() {
            var r = java.get("https://example.invalid/get", {});
            return [
                r.header("location"), r.headers()["X-Test"],
                r.cookie("sid"), r.cookies().sid,
                r.contentType(), r.charset()
            ];
        })()
        """#)
        XCTAssertEqual(result, .array([
            .string("/next"), .string("response"),
            .string("cookie-value"), .string("cookie-value"),
            .string("text/plain"), .string("UTF-8")
        ]))
    }

    func testPostPassesBodyAndHeaders() throws {
        XCTAssertEqual(
            try hostEvaluate(#"java.post('https://example.invalid/post', 'a=1', {'X-Test':'two'}).body()"#),
            .string("POST:a=1:two")
        )
    }

    func testHeadReturnsHeadResponseSnapshot() throws {
        XCTAssertEqual(
            try hostEvaluate(#"java.head('https://example.invalid/head', {}).method()"#),
            .string("HEAD")
        )
    }

    func testAjaxTransportFailureMatchesAndroidTextCategory() throws {
        let executor = JavaScriptCoreRuleJavaScriptExecutor(host: FailingJavaScriptHost())
        let value = try executor.execute(
            script: "java.ajax('https://example.invalid')",
            context: JavaScriptExecutionContext(result: .none, baseUrl: "")
        )
        guard case let .string(message) = value else {
            return XCTFail("Expected a stable error string, got \(value)")
        }
        XCTAssertTrue(message.contains("transport failed"))
        XCTAssertTrue(message.contains("offline"))
    }

    func testGetTransportFailureBecomesJavaScriptException() {
        let executor = JavaScriptCoreRuleJavaScriptExecutor(host: FailingJavaScriptHost())
        XCTAssertThrowsError(try executor.execute(
            script: "java.get('https://example.invalid', {})",
            context: JavaScriptExecutionContext(result: .none, baseUrl: "")
        )) {
            guard let error = $0 as? JavaScriptExecutionError,
                  case let .evaluationFailed(message) = error else {
                return XCTFail("Expected JavaScript evaluation failure, got \($0)")
            }
            XCTAssertTrue(message.contains("transport failed"))
        }
    }

    func testNetworkCallBudgetExceededBecomesJavaScriptException() {
        let executor = JavaScriptCoreRuleJavaScriptExecutor(
            host: ImmediateJavaScriptHost(),
            hostLimits: JavaScriptHostLimits(maximumNetworkRequestsPerExecution: 2)
        )
        XCTAssertThrowsError(try executor.execute(
            script: "java.ajax('one'); java.ajax('two'); java.ajax('three')",
            context: JavaScriptExecutionContext(result: .none, baseUrl: "")
        )) {
            guard let error = $0 as? JavaScriptExecutionError,
                  case let .evaluationFailed(message) = error else {
                return XCTFail("Expected JavaScript evaluation failure, got \($0)")
            }
            XCTAssertTrue(message.contains("request limit"))
        }
    }

    func testRequestBodyBudgetExceededBeforeHostCall() {
        let executor = JavaScriptCoreRuleJavaScriptExecutor(
            host: ImmediateJavaScriptHost(),
            hostLimits: JavaScriptHostLimits(maximumRequestBodyBytes: 3)
        )
        XCTAssertThrowsError(try executor.execute(
            script: "java.post('url', 'four', {})",
            context: JavaScriptExecutionContext(result: .none, baseUrl: "")
        ))
    }

    func testResponseBodyBudgetExceededBecomesJavaScriptException() {
        let executor = JavaScriptCoreRuleJavaScriptExecutor(
            host: ImmediateJavaScriptHost(),
            hostLimits: JavaScriptHostLimits(maximumResponseBodyBytes: 3)
        )
        XCTAssertThrowsError(try executor.execute(
            script: "java.get('https://example.invalid', {}).body()",
            context: JavaScriptExecutionContext(result: .none, baseUrl: "")
        ))
    }

    func testBudgetsAndContextsAreIsolatedAcrossExecutions() throws {
        let executor = JavaScriptCoreRuleJavaScriptExecutor(
            host: ImmediateJavaScriptHost(),
            hostLimits: JavaScriptHostLimits(maximumNetworkRequestsPerExecution: 1)
        )
        let first = try executor.execute(
            script: "java.ajax('one')",
            context: JavaScriptExecutionContext(result: .none, baseUrl: "https://one.invalid")
        )
        let second = try executor.execute(
            script: "java.ajax('two')",
            context: JavaScriptExecutionContext(result: .none, baseUrl: "https://two.invalid")
        )
        XCTAssertEqual(first, .string("ajax:one"))
        XCTAssertEqual(second, .string("ajax:two"))
    }

    private func evaluate(
        _ script: String,
        result: RuleValue = .none,
        baseUrl: String = ""
    ) throws -> JavaScriptExecutionResult {
        try executor.execute(
            script: script,
            context: JavaScriptExecutionContext(result: result, baseUrl: baseUrl)
        )
    }

    private func hostEvaluate(_ script: String) throws -> JavaScriptExecutionResult {
        try JavaScriptCoreRuleJavaScriptExecutor(host: ImmediateJavaScriptHost()).execute(
            script: script,
            context: JavaScriptExecutionContext(result: .none, baseUrl: "")
        )
    }
}

private struct ImmediateJavaScriptHost: RuleJavaScriptHost {
    func ajax(_ url: String, context: JavaScriptExecutionContext) throws -> String? {
        "ajax:\(url)"
    }

    func get(
        _ url: String,
        headers: [String: String],
        context: JavaScriptExecutionContext
    ) throws -> JavaScriptHTTPResponseSnapshot {
        response(
            body: "GET:\(headers["X-Test"] ?? "")",
            url: url,
            method: .get
        )
    }

    func post(
        _ url: String,
        body: String,
        headers: [String: String],
        context: JavaScriptExecutionContext
    ) throws -> JavaScriptHTTPResponseSnapshot {
        response(
            body: "POST:\(body):\(headers["X-Test"] ?? "")",
            url: url,
            method: .post
        )
    }

    func head(
        _ url: String,
        headers: [String: String],
        context: JavaScriptExecutionContext
    ) throws -> JavaScriptHTTPResponseSnapshot {
        response(body: "", url: url, method: .head)
    }

    private func response(
        body: String,
        url: String,
        method: JavaScriptHTTPMethod
    ) -> JavaScriptHTTPResponseSnapshot {
        JavaScriptHTTPResponseSnapshot(
            body: body,
            statusCode: 302,
            statusMessage: "Found",
            headers: ["Location": "/next", "X-Test": "response"],
            cookies: ["sid": "cookie-value"],
            url: url,
            contentType: "text/plain",
            charset: "UTF-8",
            method: method
        )
    }
}

private struct FailingJavaScriptHost: RuleJavaScriptHost {
    func ajax(_ url: String, context: JavaScriptExecutionContext) throws -> String? {
        throw JavaScriptHostError.transportFailed("offline")
    }

    func get(
        _ url: String,
        headers: [String: String],
        context: JavaScriptExecutionContext
    ) throws -> JavaScriptHTTPResponseSnapshot {
        throw JavaScriptHostError.transportFailed("offline")
    }

    func post(
        _ url: String,
        body: String,
        headers: [String: String],
        context: JavaScriptExecutionContext
    ) throws -> JavaScriptHTTPResponseSnapshot {
        throw JavaScriptHostError.transportFailed("offline")
    }

    func head(
        _ url: String,
        headers: [String: String],
        context: JavaScriptExecutionContext
    ) throws -> JavaScriptHTTPResponseSnapshot {
        throw JavaScriptHostError.transportFailed("offline")
    }
}
