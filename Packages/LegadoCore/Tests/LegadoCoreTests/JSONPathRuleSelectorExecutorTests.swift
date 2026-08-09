import Foundation
import XCTest
@testable import LegadoCore

final class JSONPathRuleSelectorExecutorTests: XCTestCase {
    private let parser = RuleParser()

    func testRootPropertyNestedAndScalarMapping() throws {
        XCTAssertEqual(try run("$.name", fixture: "basic.json"), .strings(["Legado"]))
        XCTAssertEqual(try run("$.count", fixture: "basic.json"), .strings(["3"]))
        XCTAssertEqual(try run("$.rating", fixture: "basic.json"), .strings(["4.5"]))
        XCTAssertEqual(try run("$.enabled", fixture: "basic.json"), .strings(["true"]))
        XCTAssertEqual(try run("$.missing", fixture: "basic.json"), .strings(["null"]))
        XCTAssertEqual(try run("$.store.book[0].title", fixture: "nested.json"), .strings(["A"]))
    }

    func testArrayIndexNegativeIndexWildcardNestedArrayAndEmptyArray() throws {
        XCTAssertEqual(try run("$.items[0].name", fixture: "array.json"), .strings(["first"]))
        XCTAssertEqual(try run("$.items[-1].name", fixture: "array.json"), .strings(["last"]))
        XCTAssertEqual(try run("$.items[*].name", fixture: "array.json"), .strings(["first", "second", "second", "last"]))
        XCTAssertEqual(try run("$.nested[*][1]", fixture: "array.json"), .strings(["2", "4"]))
        XCTAssertEqual(try run("$.empty[*]", fixture: "array.json"), .none)
    }

    func testRecursiveDescentProjectionUnionAndOrder() throws {
        XCTAssertEqual(try run("$..title", fixture: "nested.json"), .strings(["Child", "Deep", "A", "B", "Root"]))
        XCTAssertEqual(try run("$.items[0,2].name", fixture: "array.json"), .strings(["first", "second"]))
        XCTAssertEqual(try run("$['name','enabled']", fixture: "basic.json"), .strings(["Legado", "true"]))
    }

    func testRecursiveDescentOrderingAcrossObjectShapesAndWildcard() throws {
        let json = #"{"target":"root","child":{"target":"child","deep":{"target":"deep"}},"items":[{"target":"array-1"},{"target":"array-2"}],"sibling":{"target":"sibling"}}"#
        XCTAssertEqual(
            try run("$..target", json: json),
            .strings(["child", "deep", "array-1", "array-2", "sibling", "root"])
        )
        XCTAssertEqual(
            try run("$.child..*", json: json),
            .strings([#"{"target":"deep"}"#, "deep", "child"])
        )
        XCTAssertEqual(try run("$.items..target", json: json), .strings(["array-1", "array-2"]))
        XCTAssertEqual(try run("$.sibling..target", json: json), .strings(["sibling"]))
    }

    func testSliceAndNegativeSlice() throws {
        XCTAssertEqual(try run("$.items[1:3].name", fixture: "array.json"), .strings(["second", "second"]))
        XCTAssertEqual(try run("$.items[-2:].name", fixture: "array.json"), .strings(["second", "last"]))
        XCTAssertEqual(try run("$.items[::-1].name", fixture: "array.json"), .strings(["last", "second", "second", "first"]))
    }

    func testFilterComparisonExistenceAndBooleanOperators() throws {
        XCTAssertEqual(try run("$.items[?(@.score >= 3)].name", fixture: "array.json"), .strings(["second", "last"]))
        XCTAssertEqual(try run("$.items[?(@.name == 'second' && @.score < 3)].score", fixture: "array.json"), .strings(["2"]))
        XCTAssertEqual(try run("$.items[?(@.missing || @.score == 1)].name", fixture: "array.json"), .strings(["first"]))
    }

    func testMixedArrayObjectNestedArrayNullAndDuplicates() throws {
        XCTAssertEqual(try run("$.values", fixture: "mixed-types.json"), .strings([
            "text", "7", "2.5", "true", "false", "null", #"{"key":"value"}"#, "[1,2]"
        ]))
        XCTAssertEqual(try run("$.object", fixture: "mixed-types.json"), .strings([#"{"a":1,"b":2}"#]))
    }

    func testMissingInvalidJSONAndInvalidPathCompatibility() throws {
        XCTAssertEqual(try run("$.absent", fixture: "empty.json"), .none)
        XCTAssertEqual(try run("$.[", json: "not json"), .none)
        XCTAssertEqual(try run("$.[", fixture: "basic.json"), .none)
    }

    func testStrictErrorsAreTyped() throws {
        XCTAssertThrowsError(try run("$.name", json: "not json", policy: .strict)) {
            guard let error = $0 as? RuleExecutionError, case .invalidJSON = error else {
                return XCTFail("Unexpected error: \($0)")
            }
        }
        XCTAssertThrowsError(try run("$.[", fixture: "basic.json", policy: .strict)) {
            guard let error = $0 as? RuleExecutionError, case .invalidJSONPath = error else {
                return XCTFail("Unexpected error: \($0)")
            }
        }
        XCTAssertThrowsError(try run("$.absent", fixture: "empty.json", policy: .strict)) {
            XCTAssertEqual($0 as? RuleExecutionError, .pathNotFound("$.absent"))
        }
        XCTAssertThrowsError(try run("$.items[?(@.name =~ /second/)]", fixture: "array.json", policy: .strict)) {
            XCTAssertEqual($0 as? RuleExecutionError, .unsupportedJSONPathFeature("filter regular expressions"))
        }
    }

    func testUnicode() throws {
        XCTAssertEqual(try run("$.标题", fixture: "unicode.json"), .strings(["阅读三"]))
        XCTAssertEqual(try run("$.emoji", fixture: "unicode.json"), .strings(["📚"]))
        XCTAssertEqual(try run("$.items[*]", fixture: "unicode.json"), .strings(["第一章", "第二章"]))
    }

    func testEmbeddedJSONPathUsesDedicatedIRAndKeepsLiteralText() throws {
        let expression = try parser.parse("@Json:标题：{$.name} / {$.count}")
        guard case .jsonPathTemplate = expression else { return XCTFail("Expected jsonPathTemplate") }
        XCTAssertEqual(try run(expression, fixture: "basic.json"), .string("标题：Legado / 3"))
    }

    func testJSONPathRegexSequenceTemplateAndVariable() throws {
        XCTAssertEqual(try run(try parser.parse("$.name##ado##acy"), fixture: "basic.json"), .strings(["Legacy"]))
        XCTAssertEqual(try run(.template(TemplateExpression(parts: [
            .literal("<"), .expression(.jsonPath("$.name")), .literal(">")
        ])), fixture: "basic.json"), .string("<Legado>"))
        XCTAssertEqual(try run(.variableWrite([
            RuleVariableAssignment(key: "saved", value: .jsonPath("$.name"))
        ], .template(TemplateExpression(parts: [.expression(.variableRead("saved"))]))), fixture: "basic.json"), .string("Legado"))
    }

    func testLegadoCombinationsUseJSONPathResults() throws {
        let context = RuleParseContext(contentIsJSON: true)
        XCTAssertEqual(try run(try parser.parse("$.items[0].name&&$.items[1].name", context: context), fixture: "array.json"), .strings(["first", "second"]))
        XCTAssertEqual(try run(try parser.parse("$.missing||$.items[1].name", context: context), fixture: "array.json"), .strings(["second"]))
        XCTAssertEqual(try run(try parser.parse("$.items[0,1].name%%$.items[2,3].name", context: context), fixture: "array.json"), .strings(["first", "second", "second", "last"]))
    }

    func testAutomaticJSONContentTypingExecutesBarePropertyPath() throws {
        let expression = try parser.parse("items[1].name", context: RuleParseContext(contentIsJSON: true))
        XCTAssertEqual(try run(expression, fixture: "array.json"), .strings(["second"]))
    }

    func testJSONPathAndJSoupShareOneExecutor() throws {
        let json = #"{"html":"<p class='book'>Title</p>"}"#
        let expression = RuleExpression.sequence([
            .jsonPath("$.html"),
            .selector(SelectorRule(type: .css, value: "p.book@text"))
        ])
        XCTAssertEqual(try run(expression, json: json), .strings(["Title"]))
    }

    func testStringsInputIsAnArrayOfStringsLikeAndroid() throws {
        XCTAssertEqual(try run(.jsonPath("$[1]"), input: .strings(["{\"x\":1}", "plain"])), .strings(["plain"]))
    }

    func testRepeatedExecutionIsDeterministicAndContextsAreIsolated() throws {
        let expression = try parser.parse("$.items[*].name")
        let first = try run(expression, fixture: "array.json")
        XCTAssertEqual(first, try run(expression, fixture: "array.json"))
        var one = RuleExecutionContext(temporaryVariables: ["x": "one"])
        var two = RuleExecutionContext(temporaryVariables: ["x": "two"])
        let input = RuleExecutionInput(.string(try fixture("basic.json")))
        _ = try RuleExecutor(selectorExecutor: LegadoRuleSelectorExecutor()).execute(expression, input: input, context: &one)
        _ = try RuleExecutor(selectorExecutor: LegadoRuleSelectorExecutor()).execute(expression, input: input, context: &two)
        XCTAssertEqual(one.variable(named: "x"), "one")
        XCTAssertEqual(two.variable(named: "x"), "two")
    }

    private func run(_ path: String, fixture name: String, policy: RuleParseContext.ErrorPolicy = .legadoCompatible) throws -> RuleValue {
        try run(.jsonPath(path), json: fixture(name), policy: policy)
    }
    private func run(_ path: String, json: String, policy: RuleParseContext.ErrorPolicy = .legadoCompatible) throws -> RuleValue {
        try run(.jsonPath(path), json: json, policy: policy)
    }
    private func run(_ expression: RuleExpression, fixture name: String) throws -> RuleValue {
        try run(expression, json: fixture(name))
    }
    private func run(_ expression: RuleExpression, json: String, policy: RuleParseContext.ErrorPolicy = .legadoCompatible) throws -> RuleValue {
        try run(expression, input: .string(json), policy: policy)
    }
    private func run(_ expression: RuleExpression, input: RuleValue, policy: RuleParseContext.ErrorPolicy = .legadoCompatible) throws -> RuleValue {
        var context = RuleExecutionContext(errorPolicy: policy)
        return try RuleExecutor(selectorExecutor: LegadoRuleSelectorExecutor()).execute(
            expression, input: RuleExecutionInput(input), context: &context
        ).value
    }
    private func fixture(_ name: String) throws -> String {
        String(decoding: try FixtureLoader.data(named: name, directory: "rules/jsonpath"), as: UTF8.self)
    }
}
