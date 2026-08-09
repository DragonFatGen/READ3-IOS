import XCTest
@testable import LegadoCore

final class RuleVariableTests: XCTestCase {
    private struct LiteralSelector: RuleSelectorExecutor {
        func execute(selector: SelectorRule, input: RuleValue, context: RuleExecutionContext) throws -> RuleValue { .string(selector.value) }
        func execute(jsonPath: String, input: RuleValue, context: RuleExecutionContext) throws -> RuleValue { .string(jsonPath) }
        func execute(xpath: String, input: RuleValue, context: RuleExecutionContext) throws -> RuleValue { .string(xpath) }
    }

    func testParserPromotesPutAndGetToDedicatedIR() throws {
        XCTAssertEqual(
            try RuleParser().parse(#"@put:{"token":"value"}@get:{token}"#),
            .variableWrite(
                [RuleVariableAssignment(key: "token", value: leaf("value"))],
                .template(TemplateExpression(parts: [.expression(.variableRead("token"))]))
            )
        )
    }

    func testPutWritesEvaluatedValueAndReturnsBodyResult() throws {
        var context = RuleExecutionContext()
        let expression = try RuleParser().parse(#"@put:{"token":"value"}@get:{token}"#)
        let result = try RuleExecutor(selectorExecutor: LiteralSelector()).execute(
            expression, input: RuleExecutionInput(.string("input")), context: &context
        )
        XCTAssertEqual(result.value, .string("value"))
        XCTAssertEqual(context.variable(named: "token"), "value")
    }

    func testPutValueCanReadAnotherVariable() throws {
        XCTAssertEqual(
            try execute(
                #"@put:{"saved":"@get:{keyword}"}@get:{saved}"#,
                temporaryVariables: ["keyword": "book"]
            ),
            .string("book")
        )
    }

    func testPutWithPlainStringRemainsSupported() throws {
        XCTAssertEqual(
            try execute(#"@put:{"saved":"abc"}@get:{saved}"#),
            .string("abc")
        )
    }

    func testPutStringCanContainBraces() throws {
        XCTAssertEqual(
            try execute(#"@put:{"saved":"a{b}c"}@get:{saved}"#),
            .string("a{b}c")
        )
    }

    func testPutStringCanContainEscapedQuoteAndClosingBrace() throws {
        XCTAssertEqual(
            try execute(#"@put:{"saved":"a\"}b"}@get:{saved}"#),
            .string(#"a"}b"#)
        )
    }

    func testPutWithMultipleVariablesRemainsSupported() throws {
        var context = RuleExecutionContext()
        let result = try RuleExecutor(selectorExecutor: LiteralSelector()).execute(
            try RuleParser().parse(#"@put:{"second":"two","first":"one"}@get:{first}-@get:{second}"#),
            input: RuleExecutionInput(.none),
            context: &context
        )
        XCTAssertEqual(result.value, .string("one-two"))
        XCTAssertEqual(context.variable(named: "first"), "one")
        XCTAssertEqual(context.variable(named: "second"), "two")
    }

    func testUndefinedGetIsEmptyString() throws {
        var context = RuleExecutionContext()
        XCTAssertEqual(try RuleExecutor().execute(
            .variableRead("missing"), input: RuleExecutionInput(.none), context: &context
        ).value, .string(""))
    }

    func testTemporaryVariableOverridesSourceAndCanBeOverwritten() throws {
        var context = RuleExecutionContext(sourceVariables: ["key": "source"], temporaryVariables: ["key": "first"])
        context.setTemporaryVariable("second", named: "key")
        XCTAssertEqual(context.variable(named: "key"), "second")
    }

    func testContextsAreIsolatedAcrossExecutors() throws {
        var first = RuleExecutionContext()
        var second = RuleExecutionContext()
        let write = RuleExpression.variableWrite(
            [RuleVariableAssignment(key: "key", value: leaf("one"))], .variableRead("key")
        )
        _ = try RuleExecutor(selectorExecutor: LiteralSelector()).execute(
            write, input: RuleExecutionInput(.none), context: &first
        )
        XCTAssertEqual(first.variable(named: "key"), "one")
        XCTAssertNil(second.variable(named: "key"))
    }

    func testTemplateAndVariableComposition() throws {
        var context = RuleExecutionContext(temporaryVariables: ["chapter": "42"])
        let expression = try RuleParser().parse("chapter-@get:{chapter}")
        XCTAssertEqual(try RuleExecutor().execute(
            expression, input: RuleExecutionInput(.none), context: &context
        ).value, .string("chapter-42"))
    }

    func testRepeatedExecutionIsDeterministicAndHasNoGlobalState() throws {
        let expression = RuleExpression.variableWrite(
            [RuleVariableAssignment(key: "key", value: leaf("value"))], .variableRead("key")
        )
        var first = RuleExecutionContext()
        var second = RuleExecutionContext()
        let executor = RuleExecutor(selectorExecutor: LiteralSelector())
        let a = try executor.execute(expression, input: RuleExecutionInput(.none), context: &first).value
        let b = try executor.execute(expression, input: RuleExecutionInput(.none), context: &second).value
        XCTAssertEqual(a, b)
        XCTAssertEqual(first, second)
    }

    func testCaptureReferencesUseExtractionGroups() throws {
        var context = RuleExecutionContext()
        let expression = RuleExpression.sequence([
            .regex(RegexRule(purpose: .extraction(patterns: [#"([a-z]+)-(\d+)"#]))),
            .template(TemplateExpression(parts: [
                .expression(.captureGroup(2)), .literal(":"), .expression(.captureGroup(1)),
                .literal(":"), .expression(.captureGroup(0))
            ]))
        ])
        XCTAssertEqual(try RuleExecutor().execute(
            expression, input: RuleExecutionInput(.string("book-12")), context: &context
        ).value, .string("12:book:book-12"))
    }

    private func leaf(_ value: String) -> RuleExpression {
        .selector(SelectorRule(type: .legado, value: value))
    }

    private func execute(
        _ rule: String,
        temporaryVariables: [String: String] = [:]
    ) throws -> RuleValue {
        var context = RuleExecutionContext(temporaryVariables: temporaryVariables)
        return try RuleExecutor(selectorExecutor: LiteralSelector()).execute(
            RuleParser().parse(rule),
            input: RuleExecutionInput(.none),
            context: &context
        ).value
    }
}
