import XCTest
@testable import LegadoCore

final class TemplateExecutorTests: XCTestCase {
    func testSingleExpressionAndLiteralMix() throws {
        var context = RuleExecutionContext(temporaryVariables: ["name": "Legado"])
        let expression = RuleExpression.template(TemplateExpression(parts: [
            .literal("Hello "), .expression(.variableRead("name")), .literal("!")
        ]))
        XCTAssertEqual(try execute(expression, context: &context), .string("Hello Legado!"))
    }

    func testMultipleExpressionsAndUndefinedExpression() throws {
        var context = RuleExecutionContext(temporaryVariables: ["a": "A", "b": "B"])
        let expression = RuleExpression.template(TemplateExpression(parts: [
            .expression(.variableRead("a")), .literal("/"),
            .expression(.variableRead("missing")), .literal("/"),
            .expression(.variableRead("b"))
        ]))
        XCTAssertEqual(try execute(expression, context: &context), .string("A//B"))
    }

    func testEmptyExpressionProducesNoTextInCompatibleMode() throws {
        var context = RuleExecutionContext()
        XCTAssertEqual(try execute(
            .template(TemplateExpression(parts: [.literal("a"), .expression(.javaScript("")), .literal("b")])),
            context: &context
        ), .string("ab"))
    }

    func testExpressionReturningListUsesStringResultJoining() throws {
        var context = RuleExecutionContext()
        let extraction = RuleExpression.regex(RegexRule(purpose: .extraction(patterns: [#"(a)(b)"#])))
        XCTAssertEqual(try execute(
            .template(TemplateExpression(parts: [.literal("["), .expression(extraction), .literal("]")])),
            input: .string("ab"), context: &context
        ), .string("[ab\na\nb]"))
    }

    func testNestedRuleBodyExecutesButExpandedOuterRuleIsNotReparsed() throws {
        var context = RuleExecutionContext(temporaryVariables: ["dynamic": "a&&b"])
        let expression = RuleExpression.template(TemplateExpression(parts: [
            .expression(.variableRead("dynamic"))
        ]))
        XCTAssertEqual(try execute(expression, context: &context), .string("a&&b"))
    }

    func testTemplateCanReadResultAndBaseURL() throws {
        var context = RuleExecutionContext(baseUrl: "https://example.test/")
        let expression = RuleExpression.template(TemplateExpression(parts: [
            .expression(.variableRead("result")), .literal("@"), .expression(.variableRead("baseUrl"))
        ]))
        XCTAssertEqual(try execute(expression, input: .string("chapter"), context: &context),
                       .string("chapter@https://example.test/"))
    }

    func testTemplateInsideSequenceReceivesPreviousValue() throws {
        var context = RuleExecutionContext()
        let replace = RuleExpression.replacement(.empty, RegexRule(purpose: .replacement(
            pattern: "a", replacement: "b", replaceFirst: false
        )))
        let template = RuleExpression.template(TemplateExpression(parts: [
            .literal("<"), .expression(.variableRead("result")), .literal(">")
        ]))
        XCTAssertEqual(try execute(.sequence([replace, template]), input: .string("a"), context: &context),
                       .string("<b>"))
    }

    private func execute(
        _ expression: RuleExpression,
        input: RuleValue = .string(""),
        context: inout RuleExecutionContext
    ) throws -> RuleValue {
        try RuleExecutor().execute(expression, input: RuleExecutionInput(input), context: &context).value
    }
}
