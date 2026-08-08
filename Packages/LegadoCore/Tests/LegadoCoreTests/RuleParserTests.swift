import Foundation
import XCTest
@testable import LegadoCore

final class RuleParserTests: XCTestCase {
    private let parser = RuleParser()

    func testFixtureContainsRequiredDeterministicCases() throws {
        struct Case: Decodable { let name: String; let rule: String }
        let cases = try JSONDecoder().decode(
            [Case].self,
            from: FixtureLoader.data(named: "parser-cases.json", directory: "rules")
        )
        XCTAssertEqual(cases.count, 24)
        XCTAssertEqual(Set(cases.map(\.name)).count, 24)
    }

    func testEmptyString() throws {
        XCTAssertEqual(try parser.parse(""), .empty)
    }

    func testDefaultSelectorAndChildSequence() throws {
        XCTAssertEqual(
            try parser.parse("div.book@text"),
            .combination(.child, [
                .selector(SelectorRule(type: .legado, value: "div.book")),
                .selector(SelectorRule(type: .legado, value: "text"))
            ])
        )
    }

    func testExplicitCSS() throws {
        XCTAssertEqual(
            try parser.parse("@CSS:div.book > a@href"),
            .selector(SelectorRule(type: .css, value: "div.book > a@href"))
        )
    }

    func testJSONPathDetection() throws {
        XCTAssertEqual(try parser.parse("$.items[*].name"), .jsonPath("$.items[*].name"))
        XCTAssertEqual(try parser.parse("$[0]"), .jsonPath("$[0]"))
    }

    func testJSONContentContextDefaultsToJSONPath() throws {
        XCTAssertEqual(
            try parser.parse("items[0]", context: RuleParseContext(contentIsJSON: true)),
            .jsonPath("items[0]")
        )
    }

    func testXPathDetection() throws {
        XCTAssertEqual(try parser.parse("//div/@href"), .xpath("//div/@href"))
        XCTAssertEqual(try parser.parse("@XPath://a"), .xpath("//a"))
    }

    func testJavaScriptPrefixConsumesRemainder() throws {
        XCTAssertEqual(try parser.parse("@js:result && other"), .javaScript("result && other"))
    }

    func testJavaScriptTagCreatesPipeline() throws {
        XCTAssertEqual(
            try parser.parse("div<js>result || []</js>@text"),
            .sequence([
                .selector(SelectorRule(type: .legado, value: "div")),
                .javaScript("result || []"),
                .combination(.child, [
                    .selector(SelectorRule(type: .legado, value: "text"))
                ])
            ])
        )
    }

    func testUnterminatedJavaScriptTagRemainsOneSelectorRule() throws {
        XCTAssertEqual(
            try parser.parse("div<js>result"),
            leaf("div<js>result")
        )
    }

    func testRegexReplacementStructure() throws {
        XCTAssertEqual(
            try parser.parse(#"div@text##\s+## ##"#),
            .replacement(
                .combination(.child, [
                    .selector(SelectorRule(type: .legado, value: "div")),
                    .selector(SelectorRule(type: .legado, value: "text"))
                ]),
                RegexRule(purpose: .replacement(pattern: #"\s+"#, replacement: " ", replaceFirst: true))
            )
        )
    }

    func testAllInOneRegexExtractionChain() throws {
        XCTAssertEqual(
            try parser.parse(":first&&second", context: RuleParseContext(allInOne: true)),
            .regex(RegexRule(purpose: .extraction(patterns: ["first", "second"])))
        )
    }

    func testTemplateWithLiteralParts() throws {
        XCTAssertEqual(
            try parser.parse("prefix-{{result.name}}-suffix"),
            .template(TemplateExpression(parts: [
                .literal("prefix-"),
                .expression(.javaScript("result.name")),
                .literal("-suffix")
            ]))
        )
    }

    func testMultipleTemplatesAndEmptyTemplate() throws {
        XCTAssertEqual(
            try parser.parse("{{a}}/{{}}/{{$.name}}"),
            .template(TemplateExpression(parts: [
                .expression(.javaScript("a")),
                .literal("/"),
                .expression(.javaScript("")),
                .literal("/"),
                .expression(.jsonPath("$.name"))
            ]))
        )
    }

    func testConcatenateCombination() throws {
        XCTAssertEqual(
            try parser.parse("a&&b"),
            .combination(.concatenate, [leaf("a"), leaf("b")])
        )
    }

    func testFallbackCombination() throws {
        XCTAssertEqual(
            try parser.parse("a||b"),
            .combination(.fallback, [leaf("a"), leaf("b")])
        )
    }

    func testInterleaveCombination() throws {
        XCTAssertEqual(
            try parser.parse("a%%b"),
            .combination(.interleave, [leaf("a"), leaf("b")])
        )
    }

    func testThreePartCombinationPreservesOrder() throws {
        XCTAssertEqual(
            try parser.parse("a&&b&&c"),
            .combination(.concatenate, [leaf("a"), leaf("b"), leaf("c")])
        )
    }

    func testFirstTopLevelOperatorDeterminesOuterCombination() throws {
        XCTAssertEqual(
            try parser.parse("a&&b||c"),
            .combination(.concatenate, [
                leaf("a"),
                .combination(.fallback, [leaf("b"), leaf("c")])
            ])
        )
    }

    func testOperatorsInsideJSONFilterAreProtected() throws {
        let rule = "$[?(@.a && @.b || @.c)]"
        XCTAssertEqual(try parser.parse(rule), .jsonPath(rule))
    }

    func testOperatorsInsideJavaScriptAreProtected() throws {
        XCTAssertEqual(try parser.parse("@js:a && b || c"), .javaScript("a && b || c"))
    }

    func testOperatorInsideRegexReplacementPatternIsProtected() throws {
        XCTAssertEqual(
            try parser.parse("div##a&&b##x"),
            .replacement(
                leaf("div"),
                RegexRule(purpose: .replacement(pattern: "a&&b", replacement: "x", replaceFirst: false))
            )
        )
    }

    func testOperatorInsideTemplateIsProtected() throws {
        XCTAssertEqual(
            try parser.parse("a{{left&&right}}b"),
            .template(TemplateExpression(parts: [
                .literal("a"), .expression(.javaScript("left&&right")), .literal("b")
            ]))
        )
    }

    func testEscapedOperatorRemainsSelectorText() throws {
        XCTAssertEqual(try parser.parse(#"a\&&b"#), leaf(#"a\&&b"#))
    }

    func testEmptySubruleIsPreservedInCompatibleMode() throws {
        XCTAssertEqual(
            try parser.parse("a&&"),
            .combination(.concatenate, [leaf("a"), .empty])
        )
    }

    func testEmptySubruleIsDiagnosedInStrictMode() {
        XCTAssertThrowsError(
            try parser.parse("a&&", context: RuleParseContext(errorPolicy: .strict))
        ) {
            XCTAssertEqual($0 as? RuleSyntaxError, .invalidOperatorSequence(operator: .concatenate, offset: 1))
        }
    }

    func testMalformedRegexIsKeptStructuralWithoutCompilation() throws {
        XCTAssertEqual(
            try parser.parse("a##[##b"),
            .replacement(
                leaf("a"),
                RegexRule(purpose: .replacement(pattern: "[", replacement: "b", replaceFirst: false))
            )
        )
    }

    func testUnterminatedTemplateIsLiteralInCompatibleMode() throws {
        XCTAssertEqual(
            try parser.parse("a{{result"),
            .template(TemplateExpression(parts: [.literal("a"), .literal("{{result")]))
        )
    }

    func testUnterminatedTemplateIsDiagnosedInStrictMode() {
        XCTAssertThrowsError(
            try parser.parse("a{{result", context: RuleParseContext(errorPolicy: .strict))
        ) {
            XCTAssertEqual($0 as? RuleSyntaxError, .unterminatedTemplate(offset: 1))
        }
    }

    func testUnbalancedSelectorGroupIsDiagnosed() {
        XCTAssertThrowsError(try parser.parse("$[?(@.name")) {
            XCTAssertEqual($0 as? RuleSyntaxError, .unbalancedGroup(opening: "(", offset: 3))
        }
    }

    func testTokenizerReportsOperatorsAndOffsets() {
        let tokens = parser.tokenize("a&&{{b}}##c")
        XCTAssertTrue(tokens.contains(RuleToken(kind: .operatorSymbol(.concatenate), lexeme: "&&", offset: 1)))
        XCTAssertTrue(tokens.contains(RuleToken(kind: .templateStart, lexeme: "{{", offset: 3)))
        XCTAssertTrue(tokens.contains(RuleToken(kind: .regexDelimiter, lexeme: "##", offset: 8)))
        XCTAssertEqual(
            parser.tokenize("@js:a&&b").first,
            RuleToken(kind: .javaScriptStart, lexeme: "@js:", offset: 0)
        )
    }

    func testRepeatedParsingIsDeterministic() throws {
        let rule = "a&&{{result}}##x##y"
        XCTAssertEqual(try parser.parse(rule), try parser.parse(rule))
    }

    func testParserHasNoCrossCallState() throws {
        _ = try parser.parse(":first&&second", context: RuleParseContext(allInOne: true))
        XCTAssertEqual(try parser.parse("ordinary"), leaf("ordinary"))
    }

    private func leaf(_ value: String) -> RuleExpression {
        .selector(SelectorRule(type: .legado, value: value))
    }
}
