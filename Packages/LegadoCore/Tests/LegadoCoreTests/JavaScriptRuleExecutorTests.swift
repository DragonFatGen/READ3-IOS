import Foundation
import XCTest
@testable import LegadoCore

final class JavaScriptRuleExecutorTests: XCTestCase {
    func testEmptyJavaScriptReturnsNoneWithoutCallingExecutor() throws {
        let fake = FakeRuleJavaScriptExecutor(returning: .string("unused"))
        XCTAssertEqual(try execute(.javaScript(""), with: fake), .none)
        XCTAssertEqual(fake.executionCount, 0)
    }

    func testMissingJavaScriptExecutorFailsExplicitly() {
        var context = RuleExecutionContext()
        XCTAssertThrowsError(try RuleExecutor().execute(
            .javaScript("result"), input: RuleExecutionInput(.string("input")), context: &context
        )) {
            XCTAssertEqual($0 as? RuleExecutionError, .unsupportedExecutionNode("JavaScript"))
        }
    }

    func testInjectedExecutorExecutesOnce() throws {
        let fake = FakeRuleJavaScriptExecutor(returning: .string("value"))
        XCTAssertEqual(try execute(.javaScript("result"), with: fake), .string("value"))
        XCTAssertEqual(fake.executionCount, 1)
    }

    func testScriptTextIsPassedWithoutTrimmingOrReparsing() throws {
        let script = "  result && left || right;\n"
        let fake = FakeRuleJavaScriptExecutor(returning: .string("value"))
        _ = try execute(.javaScript(script), with: fake)
        XCTAssertEqual(fake.scripts, [script])
    }

    func testCurrentInputIsExposedAsResult() throws {
        let fake = FakeRuleJavaScriptExecutor(returning: .string("value"))
        _ = try execute(.javaScript("result"), input: .strings(["a", "b"]), with: fake)
        XCTAssertEqual(fake.contexts.first?.result, .strings(["a", "b"]))
    }

    func testBaseUrlIsSnapshotted() throws {
        let fake = FakeRuleJavaScriptExecutor(returning: .string("value"))
        var context = RuleExecutionContext(baseUrl: "https://example.invalid/books/1")
        _ = try RuleExecutor(javaScriptExecutor: fake).execute(
            .javaScript("baseUrl"), input: RuleExecutionInput(.none), context: &context
        )
        XCTAssertEqual(fake.contexts.first?.baseUrl, "https://example.invalid/books/1")
    }

    func testSourceVariablesAreSnapshotted() throws {
        let fake = FakeRuleJavaScriptExecutor(returning: .string("value"))
        var context = RuleExecutionContext(sourceVariables: ["sourceToken": "one"])
        _ = try RuleExecutor(javaScriptExecutor: fake).execute(
            .javaScript("result"), input: RuleExecutionInput(.none), context: &context
        )
        XCTAssertEqual(fake.contexts.first?.sourceVariables, ["sourceToken": "one"])
    }

    func testTemporaryVariablesAreSnapshotted() throws {
        let fake = FakeRuleJavaScriptExecutor(returning: .string("value"))
        var context = RuleExecutionContext(temporaryVariables: ["chapterId": "42"])
        _ = try RuleExecutor(javaScriptExecutor: fake).execute(
            .javaScript("result"), input: RuleExecutionInput(.none), context: &context
        )
        XCTAssertEqual(fake.contexts.first?.temporaryVariables, ["chapterId": "42"])
    }

    func testExecutorStringResultMapsToRuleString() throws {
        XCTAssertEqual(try execute(.javaScript("'text'"), returning: .string("text")), .string("text"))
    }

    func testExecutorArrayResultMapsToRuleStrings() throws {
        XCTAssertEqual(
            try execute(.javaScript("['a', 'b']"), returning: .array([.string("a"), .string("b")])),
            .strings(["a", "b"])
        )
    }

    func testUndefinedAndNullMapToNone() throws {
        XCTAssertEqual(try execute(.javaScript("undefined"), returning: .undefined), .none)
        XCTAssertEqual(try execute(.javaScript("null"), returning: .null), .none)
    }

    func testBooleanAndNumberUseAndroidScalarSpelling() throws {
        XCTAssertEqual(try execute(.javaScript("true"), returning: .boolean(true)), .string("true"))
        XCTAssertEqual(try execute(.javaScript("1"), returning: .number(1)), .string("1.0"))
        XCTAssertEqual(try execute(.javaScript("1.5"), returning: .number(1.5)), .string("1.5"))
    }

    func testObjectUsesDeterministicSortedCompactJSON() throws {
        let object: JavaScriptExecutionResult = .object(["z": .number(2), "a": .string("x")])
        XCTAssertEqual(try execute(.javaScript("({z: 2, a: 'x'})"), returning: object), .string(#"{"a":"x","z":2.0}"#))
    }

    func testExecutorErrorPropagatesInCompatibleMode() {
        let fake = FakeRuleJavaScriptExecutor(throwing: .evaluationFailed("ReferenceError"))
        var context = RuleExecutionContext()
        XCTAssertThrowsError(try RuleExecutor(javaScriptExecutor: fake).execute(
            .javaScript("missing"), input: RuleExecutionInput(.none), context: &context
        )) {
            XCTAssertEqual($0 as? JavaScriptExecutionError, .evaluationFailed("ReferenceError"))
        }
    }

    func testExecutorErrorPropagatesInStrictMode() {
        let fake = FakeRuleJavaScriptExecutor(throwing: .evaluationFailed("TypeError"))
        var context = RuleExecutionContext(errorPolicy: .strict)
        XCTAssertThrowsError(try RuleExecutor(javaScriptExecutor: fake).execute(
            .javaScript("bad()"), input: RuleExecutionInput(.none), context: &context
        )) {
            XCTAssertEqual($0 as? JavaScriptExecutionError, .evaluationFailed("TypeError"))
        }
    }

    func testSelectorFeedsJavaScriptResultBinding() throws {
        let fake = FakeRuleJavaScriptExecutor(returning: .string("js"))
        var context = RuleExecutionContext()
        let result = try RuleExecutor(selectorExecutor: PipelineSelector(), javaScriptExecutor: fake).execute(
            .sequence([leaf("selected"), .javaScript("result")]),
            input: RuleExecutionInput(.string("input")), context: &context
        )
        XCTAssertEqual(result.value, .string("js"))
        XCTAssertEqual(fake.contexts.first?.result, .string("input-selected"))
    }

    func testRegexFeedsJavaScriptResultBinding() throws {
        let fake = FakeRuleJavaScriptExecutor(returning: .string("js"))
        var context = RuleExecutionContext()
        let replace = RuleExpression.replacement(.empty, replacement("a", "b"))
        _ = try RuleExecutor(javaScriptExecutor: fake).execute(
            .sequence([replace, .javaScript("result")]),
            input: RuleExecutionInput(.string("a")), context: &context
        )
        XCTAssertEqual(fake.contexts.first?.result, .string("b"))
    }

    func testJavaScriptFeedsRegex() throws {
        let fake = FakeRuleJavaScriptExecutor(returning: .string("a-a"))
        var context = RuleExecutionContext()
        let expression = RuleExpression.sequence([
            .javaScript("'a-a'"), .replacement(.empty, replacement("a", "b"))
        ])
        XCTAssertEqual(try RuleExecutor(javaScriptExecutor: fake).execute(
            expression, input: RuleExecutionInput(.string("seed")), context: &context
        ).value, .string("b-b"))
    }

    func testJavaScriptFeedsTemplate() throws {
        let fake = FakeRuleJavaScriptExecutor(results: [.string("alpha"), .string("alpha")])
        let template = TemplateExpression(parts: [
            .literal("value="), .expression(.javaScript("result"))
        ])
        XCTAssertEqual(
            try execute(.sequence([.javaScript("'alpha'"), .template(template)]), with: fake),
            .string("value=alpha")
        )
        XCTAssertEqual(fake.contexts.map(\.result), [.string("seed"), .string("alpha")])
    }

    func testIntegralTemplateNumberOmitsPointZero() throws {
        let template = RuleExpression.template(TemplateExpression(parts: [
            .literal("page="), .expression(.javaScript("1"))
        ]))
        XCTAssertEqual(try execute(template, returning: .number(1)), .string("page=1"))
    }

    func testJavaScriptCanSupplyVariableWriteValue() throws {
        let fake = FakeRuleJavaScriptExecutor(returning: .string("token"))
        let expression = RuleExpression.variableWrite(
            [RuleVariableAssignment(key: "saved", value: .javaScript("'token'"))],
            .variableRead("saved")
        )
        XCTAssertEqual(try execute(expression, with: fake), .string("token"))
    }

    func testCombinationEvaluatesJavaScriptBranchesInOrder() throws {
        let fake = FakeRuleJavaScriptExecutor(results: [.string("a"), .string("b")])
        let expression = RuleExpression.combination(.concatenate, [
            .javaScript("'a'"), .javaScript("'b'")
        ])
        XCTAssertEqual(try execute(expression, with: fake), .strings(["a", "b"]))
        XCTAssertEqual(fake.scripts, ["'a'", "'b'"])
    }

    func testRepeatedExecutionsAreDeterministic() throws {
        let fake = FakeRuleJavaScriptExecutor(results: [.string("same"), .string("same")])
        var first = RuleExecutionContext(baseUrl: "https://example.invalid")
        var second = RuleExecutionContext(baseUrl: "https://example.invalid")
        let executor = RuleExecutor(javaScriptExecutor: fake)
        let a = try executor.execute(.javaScript("'same'"), input: RuleExecutionInput(.none), context: &first)
        let b = try executor.execute(.javaScript("'same'"), input: RuleExecutionInput(.none), context: &second)
        XCTAssertEqual(a, b)
    }

    func testExecutionContextSnapshotsAreIsolated() throws {
        let fake = FakeRuleJavaScriptExecutor(results: [.string("one"), .string("two")])
        var first = RuleExecutionContext(temporaryVariables: ["id": "one"])
        var second = RuleExecutionContext(temporaryVariables: ["id": "two"])
        let executor = RuleExecutor(javaScriptExecutor: fake)
        _ = try executor.execute(.javaScript("result"), input: RuleExecutionInput(.none), context: &first)
        _ = try executor.execute(.javaScript("result"), input: RuleExecutionInput(.none), context: &second)
        XCTAssertEqual(fake.contexts.map(\.temporaryVariables), [["id": "one"], ["id": "two"]])
    }

    func testIndependentRuleExecutorsCanRunConcurrently() {
        let values = ThreadSafeStrings()
        DispatchQueue.concurrentPerform(iterations: 24) { index in
            let fixed = FixedRuleJavaScriptExecutor(result: .string("v\(index)"))
            var context = RuleExecutionContext(baseUrl: "https://example.invalid/\(index)")
            let result = try? RuleExecutor(javaScriptExecutor: fixed).execute(
                .javaScript("result"), input: RuleExecutionInput(.none), context: &context
            ).value.stringValue
            if let result { values.append(result) }
        }
        XCTAssertEqual(Set(values.snapshot), Set((0..<24).map { "v\($0)" }))
    }

    func testSelectorOnlyInitializerBehaviorDoesNotChange() {
        var context = RuleExecutionContext()
        let executor = RuleExecutor(selectorExecutor: PipelineSelector())
        XCTAssertThrowsError(try executor.execute(
            .javaScript("result"), input: RuleExecutionInput(.none), context: &context
        )) {
            XCTAssertEqual($0 as? RuleExecutionError, .unsupportedExecutionNode("JavaScript"))
        }
    }

    private func execute(
        _ expression: RuleExpression,
        input: RuleValue = .string("seed"),
        returning result: JavaScriptExecutionResult
    ) throws -> RuleValue {
        try execute(expression, input: input, with: FakeRuleJavaScriptExecutor(returning: result))
    }

    private func execute(
        _ expression: RuleExpression,
        input: RuleValue = .string("seed"),
        with executor: any RuleJavaScriptExecutor
    ) throws -> RuleValue {
        var context = RuleExecutionContext()
        return try RuleExecutor(javaScriptExecutor: executor).execute(
            expression, input: RuleExecutionInput(input), context: &context
        ).value
    }

    private func leaf(_ value: String) -> RuleExpression {
        .selector(SelectorRule(type: .legado, value: value))
    }

    private func replacement(_ pattern: String, _ value: String) -> RegexRule {
        RegexRule(purpose: .replacement(pattern: pattern, replacement: value, replaceFirst: false))
    }
}

private struct FixedRuleJavaScriptExecutor: RuleJavaScriptExecutor {
    let result: JavaScriptExecutionResult

    func execute(script: String, context: JavaScriptExecutionContext) throws -> JavaScriptExecutionResult {
        result
    }
}

/// Locking makes the concurrent-test result collector safely Sendable.
private final class ThreadSafeStrings: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [String] = []

    func append(_ value: String) {
        lock.withLock { values.append(value) }
    }

    var snapshot: [String] {
        lock.withLock { values }
    }
}

/// Locking makes the mutable capture state safe while XCTest invokes Sendable
/// executors from concurrent tests.
private final class FakeRuleJavaScriptExecutor: RuleJavaScriptExecutor, @unchecked Sendable {
    private let lock = NSLock()
    private var outcomes: [Result<JavaScriptExecutionResult, JavaScriptExecutionError>]
    private var capturedScripts: [String] = []
    private var capturedContexts: [JavaScriptExecutionContext] = []

    init(results: [JavaScriptExecutionResult]) {
        outcomes = results.map(Result.success)
    }

    convenience init(returning result: JavaScriptExecutionResult) {
        self.init(results: [result])
    }

    init(throwing error: JavaScriptExecutionError) {
        outcomes = [.failure(error)]
    }

    var scripts: [String] {
        lock.withLock { capturedScripts }
    }

    var contexts: [JavaScriptExecutionContext] {
        lock.withLock { capturedContexts }
    }

    var executionCount: Int {
        lock.withLock { capturedScripts.count }
    }

    func execute(script: String, context: JavaScriptExecutionContext) throws -> JavaScriptExecutionResult {
        try lock.withLock {
            capturedScripts.append(script)
            capturedContexts.append(context)
            guard !outcomes.isEmpty else {
                throw JavaScriptExecutionError.evaluationFailed("No configured fake result")
            }
            return try outcomes.removeFirst().get()
        }
    }
}

private struct PipelineSelector: RuleSelectorExecutor {
    func execute(selector: SelectorRule, input: RuleValue, context: RuleExecutionContext) throws -> RuleValue {
        .string(input.stringValue + "-" + selector.value)
    }

    func execute(jsonPath: String, input: RuleValue, context: RuleExecutionContext) throws -> RuleValue {
        .string(jsonPath)
    }

    func execute(xpath: String, input: RuleValue, context: RuleExecutionContext) throws -> RuleValue {
        .string(xpath)
    }
}
