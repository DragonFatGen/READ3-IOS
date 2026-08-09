import XCTest
@testable import LegadoCore

final class RegexExecutorTests: XCTestCase {
    func testReplaceAllAndUnicode() throws {
        XCTAssertEqual(try replace(#"猫+"#, with: "犬", in: "猫猫-a-猫"), .string("犬-a-犬"))
    }

    func testReplaceFirstMatchesAndroidMatchedFragmentBehavior() throws {
        XCTAssertEqual(try replace(#"\d+"#, with: "x", in: "a12b34", first: true), .string("x"))
        XCTAssertEqual(try replace(#"\d+"#, with: "x", in: "abc", first: true), .string(""))
    }

    func testReplacementCaptureGroupsZeroOneAndTwo() throws {
        XCTAssertEqual(
            try replace(#"([a-z]+)-(\d+)"#, with: "$0/$1/$2", in: "ab-12"),
            .string("ab-12/ab/12")
        )
    }

    func testEmptyReplacementAndNoMatch() throws {
        XCTAssertEqual(try replace("x", with: "", in: "xax"), .string("a"))
        XCTAssertEqual(try replace("z", with: "q", in: "xax"), .string("xax"))
    }

    func testInvalidRegexFallsBackToLiteralInCompatibleMode() throws {
        XCTAssertEqual(try replace("[", with: "x", in: "a[b"), .string("axb"))
    }

    func testInvalidRegexThrowsInStrictMode() {
        var context = RuleExecutionContext(errorPolicy: .strict)
        XCTAssertThrowsError(try RuleExecutor().execute(
            .replacement(.empty, RegexRule(purpose: .replacement(pattern: "[", replacement: "x", replaceFirst: false))),
            input: RuleExecutionInput(.string("a[b")), context: &context
        )) { XCTAssertEqual($0 as? RuleExecutionError, .invalidRegularExpression("[")) }
    }

    func testExtractionReturnsAllCaptureGroupsAndUpdatesContext() throws {
        var context = RuleExecutionContext()
        let result = try RuleExecutor().execute(
            .regex(RegexRule(purpose: .extraction(patterns: [#"([a-z]+)-(\d+)"#]))),
            input: RuleExecutionInput(.string("ab-12")), context: &context
        )
        XCTAssertEqual(result.value, .strings(["ab-12", "ab", "12"]))
        XCTAssertEqual(context.captureGroups, ["ab-12", "ab", "12"])
    }

    func testExtractionNoMatchIsNone() throws {
        var context = RuleExecutionContext()
        XCTAssertEqual(
            try RuleExecutor().execute(
                .regex(RegexRule(purpose: .extraction(patterns: ["z+"]))),
                input: RuleExecutionInput(.string("abc")), context: &context
            ).value,
            .none
        )
    }

    func testSequenceAndCombinationWithRegex() throws {
        let first = RegexRule(purpose: .replacement(pattern: "a", replacement: "b", replaceFirst: false))
        let second = RegexRule(purpose: .replacement(pattern: "b", replacement: "c", replaceFirst: false))
        var sequenceContext = RuleExecutionContext()
        XCTAssertEqual(try RuleExecutor().execute(
            .sequence([.replacement(.empty, first), .replacement(.empty, second)]),
            input: RuleExecutionInput(.string("a")), context: &sequenceContext
        ).value, .string("c"))
        var combinationContext = RuleExecutionContext()
        XCTAssertEqual(try RuleExecutor().execute(
            .combination(.concatenate, [.replacement(.empty, first), .replacement(.empty, second)]),
            input: RuleExecutionInput(.string("a")), context: &combinationContext
        ).value, .strings(["b", "a"]))
    }

    private func replace(_ pattern: String, with replacement: String, in input: String, first: Bool = false) throws -> RuleValue {
        var context = RuleExecutionContext()
        return try RuleExecutor().execute(
            .replacement(.empty, RegexRule(purpose: .replacement(
                pattern: pattern, replacement: replacement, replaceFirst: first
            ))),
            input: RuleExecutionInput(.string(input)), context: &context
        ).value
    }
}
