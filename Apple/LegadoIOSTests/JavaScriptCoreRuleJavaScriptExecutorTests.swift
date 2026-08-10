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
}
