import Foundation
import XCTest
@testable import LegadoCore

final class RuleExecutorTests: XCTestCase {
    private struct StubSelector: RuleSelectorExecutor {
        func execute(selector: SelectorRule, input: RuleValue) throws -> RuleValue {
            switch selector.value {
            case "none": return .none
            case "empty": return .string("")
            default: return .string(input.stringValue + selector.value)
            }
        }
        func execute(jsonPath: String, input: RuleValue) throws -> RuleValue { .string(jsonPath) }
        func execute(xpath: String, input: RuleValue) throws -> RuleValue { .string(xpath) }
    }

    func testExecutionFixtureContainsDeterministicCases() throws {
        struct Case: Decodable { let name: String; let rule: String }
        let data = try FixtureLoader.data(named: "executor-cases.json", directory: "rules/execution")
        let cases = try JSONDecoder().decode([Case].self, from: data)
        XCTAssertEqual(cases.count, 7)
        XCTAssertEqual(Set(cases.map(\.name)).count, 7)
    }

    func testEmptyDistinguishesNoResultFromEmptyString() throws {
        var context = RuleExecutionContext()
        let result = try RuleExecutor().execute(.empty, input: RuleExecutionInput(.string("")), context: &context)
        XCTAssertEqual(result.value, .none)
        XCTAssertNotEqual(result.value, .string(""))
    }

    func testSequenceFeedsABIntoC() throws {
        var context = RuleExecutionContext()
        let expression = RuleExpression.sequence([leaf("A"), leaf("B"), leaf("C")])
        let result = try RuleExecutor(selectorExecutor: StubSelector()).execute(
            expression, input: RuleExecutionInput(.string("")), context: &context
        )
        XCTAssertEqual(result.value, .string("ABC"))
    }

    func testSequenceStopsAtNoneButContinuesWithEmptyString() throws {
        var first = RuleExecutionContext()
        XCTAssertEqual(
            try RuleExecutor(selectorExecutor: StubSelector()).execute(
                .sequence([leaf("none"), leaf("B")]), input: RuleExecutionInput(.string("x")), context: &first
            ).value,
            .none
        )
        var second = RuleExecutionContext()
        XCTAssertEqual(
            try RuleExecutor(selectorExecutor: StubSelector()).execute(
                .sequence([leaf("empty"), leaf("B")]), input: RuleExecutionInput(.string("x")), context: &second
            ).value,
            .string("B")
        )
    }

    func testConcatenateEvaluatesEveryNonEmptyBranch() throws {
        var context = RuleExecutionContext()
        let result = try RuleExecutor(selectorExecutor: StubSelector()).execute(
            .combination(.concatenate, [leaf("A"), leaf("none"), leaf("B")]),
            input: RuleExecutionInput(.string("")), context: &context
        )
        XCTAssertEqual(result.value, .strings(["A", "B"]))
    }

    func testFallbackReturnsFirstNonEmptyValue() throws {
        var context = RuleExecutionContext()
        let result = try RuleExecutor(selectorExecutor: StubSelector()).execute(
            .combination(.fallback, [leaf("empty"), leaf("A"), leaf("B")]),
            input: RuleExecutionInput(.string("")), context: &context
        )
        XCTAssertEqual(result.value, .string("A"))
    }

    func testInterleaveUsesFirstNonEmptyListAsOuterBound() throws {
        var context = RuleExecutionContext()
        let expression = RuleExpression.combination(.interleave, [
            extraction(#"(a)(b)"#), extraction(#"(1)"#), extraction(#"(X)(Y)(Z)"#)
        ])
        let result = try RuleExecutor().execute(
            expression, input: RuleExecutionInput(.string("ab1XYZ")), context: &context
        )
        XCTAssertEqual(result.value, .strings(["ab", "1", "XYZ", "a", "1", "X", "b", "Y"]))
    }

    func testNestedCombinationAndThreeBranches() throws {
        var context = RuleExecutionContext()
        let expression = RuleExpression.combination(.concatenate, [
            leaf("A"), .combination(.fallback, [leaf("none"), leaf("B")]), leaf("C")
        ])
        XCTAssertEqual(
            try RuleExecutor(selectorExecutor: StubSelector()).execute(
                expression, input: RuleExecutionInput(.string("")), context: &context
            ).value,
            .strings(["A", "B", "C"])
        )
    }

    func testUnsupportedSelectorNodesFailExplicitly() {
        var context = RuleExecutionContext()
        XCTAssertThrowsError(try RuleExecutor().execute(
            leaf("a"), input: RuleExecutionInput(.string("x")), context: &context
        )) { XCTAssertEqual($0 as? RuleExecutionError, .unsupportedExecutionNode("selector")) }
    }

    private func leaf(_ value: String) -> RuleExpression {
        .selector(SelectorRule(type: .legado, value: value))
    }
    private func extraction(_ pattern: String) -> RuleExpression {
        .regex(RegexRule(purpose: .extraction(patterns: [pattern])))
    }
}
