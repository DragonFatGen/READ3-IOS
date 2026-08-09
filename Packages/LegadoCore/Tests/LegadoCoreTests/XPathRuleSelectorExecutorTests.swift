import Foundation
import XCTest
@testable import LegadoCore

final class XPathRuleSelectorExecutorTests: XCTestCase {
    private let parser = RuleParser()

    func testRootCurrentAndAbsoluteChildPath() throws {
        let root = try run(".", fixture: "basic.html")
        XCTAssertEqual(root.stringValues.count, 1)
        XCTAssertTrue(root.stringValue.contains("<html>"))
        XCTAssertEqual(try run("/body/main/h1/text()", fixture: "basic.html"), .strings(["Heading"]))
    }

    func testDescendantElementAndNestedPath() throws {
        let elements = try run("//section/div/span", fixture: "nested.html")
        XCTAssertEqual(elements.stringValues.count, 2)
        XCTAssertTrue(elements.stringValues[0].contains("Deep One"))
        XCTAssertEqual(try run("//section/div/span/text()", fixture: "nested.html"), .strings(["Deep One", "Deep Two"]))
    }

    func testTextReturnsIndependentNormalizedTextNodes() throws {
        XCTAssertEqual(try run("//p/text()", fixture: "basic.html"), .strings(["Hello", "!"]))
        XCTAssertEqual(try run("//p//text()", fixture: "basic.html"), .strings(["Hello", "world", "!"]))
    }

    func testAttributesKeepRawRelativeURLsAndRecursiveAttributeProjection() throws {
        XCTAssertEqual(try run("//a/@href", fixture: "attributes.html"), .strings(["/first", "relative/second"]))
        XCTAssertEqual(try run("//@data-id", fixture: "attributes.html"), .strings(["a1", "a2", "box"]))
    }

    func testMultipleNodesNoMatchAndEmptyAttribute() throws {
        XCTAssertEqual(try run("//a/text()", fixture: "attributes.html"), .strings(["First", "Second"]))
        XCTAssertEqual(try run("//missing", fixture: "attributes.html"), .none)
        XCTAssertEqual(try run("//div/@missing", fixture: "attributes.html"), .strings([""]))
    }

    func testIndexLastAndPositionPredicatesUseSameTagPositions() throws {
        XCTAssertEqual(try run("//ul/li[1]/text()", fixture: "lists.html"), .strings(["Alpha"]))
        XCTAssertEqual(try run("//ul/li[last()]/text()", fixture: "lists.html"), .strings(["Gamma"]))
        XCTAssertEqual(try run("//ol/li[position()=1]/text()", fixture: "lists.html"), .strings(["One"]))
    }

    func testAttributeEqualityExistenceContainsAndStartsWithPredicates() throws {
        XCTAssertEqual(try run("//a[@data-id='a2']/text()", fixture: "attributes.html"), .strings(["Second"]))
        XCTAssertEqual(try run("//a[@href]/text()", fixture: "attributes.html"), .strings(["First", "Second"]))
        XCTAssertEqual(try run("//a[contains(@class,'primary')]/text()", fixture: "attributes.html"), .strings(["First"]))
        XCTAssertEqual(try run("//a[starts-with(@href,'relative')]/text()", fixture: "attributes.html"), .strings(["Second"]))
    }

    func testTextEqualityPredicate() throws {
        XCTAssertEqual(try run("//li[text()='Beta']/text()", fixture: "lists.html"), .strings(["Beta"]))
    }

    func testCountAndTopLevelBooleanMapping() throws {
        XCTAssertEqual(try run("count(//ul/li)", fixture: "lists.html"), .strings(["3.0"]))
        XCTAssertEqual(try run("contains('Legado','gad')", fixture: "basic.html"), .strings(["true"]))
        XCTAssertEqual(try run("starts-with('Legado','Read')", fixture: "basic.html"), .strings(["false"]))
    }

    func testAndroidUnsupportedStringAndNormalizeSpaceAreExplicit() throws {
        XCTAssertThrowsError(try run("string(//title)", fixture: "basic.html")) {
            XCTAssertEqual($0 as? RuleExecutionError, .unsupportedXPathFeature("string()"))
        }
        XCTAssertThrowsError(try run("normalize-space(//title)", fixture: "basic.html")) {
            XCTAssertEqual($0 as? RuleExecutionError, .unsupportedXPathFeature("normalize-space()"))
        }
    }

    func testNodeAndJsoupXpathExtensionNodeTests() throws {
        let nodes = try run("//main/node()", fixture: "basic.html")
        XCTAssertEqual(nodes.stringValues.count, 2)
        XCTAssertTrue(nodes.stringValues[0].contains("<h1>"))
        XCTAssertEqual(try run("//main/allText()", fixture: "basic.html"), .strings(["Heading Hello world !"]))
        XCTAssertTrue(try run("//main/html()", fixture: "basic.html").stringValue.contains("<h1>"))
        XCTAssertTrue(try run("//main/outerHtml()", fixture: "basic.html").stringValue.contains("<main>"))
    }

    func testParentAndRelativeXPath() throws {
        let parent = try run("//span/..", fixture: "nested.html")
        XCTAssertEqual(parent.stringValues.count, 2)
        XCTAssertTrue(parent.stringValues[0].contains("<div>"))
        XCTAssertEqual(try run("body/main/h1/text()", fixture: "basic.html"), .strings(["Heading"]))
    }

    func testUnicode() throws {
        XCTAssertEqual(try run("//h1/text()", fixture: "unicode.html"), .strings(["阅读三 📚"]))
        XCTAssertEqual(try run("//li/@data-id", fixture: "unicode.html"), .strings(["章节一", "章节二"]))
    }

    func testMalformedHTMLUsesSwiftSoupRecovery() throws {
        let result = try run("//div[@class='card']/h2/text()", fixture: "malformed.html")
        XCTAssertFalse(result.isEmpty)
        XCTAssertTrue(result.stringValue.contains("Broken title"))
    }

    func testInvalidXPathThrowsTypedErrorInCompatibleAndStrictModes() throws {
        for policy in [RuleParseContext.ErrorPolicy.legadoCompatible, .strict] {
            XCTAssertThrowsError(try run("//div[", fixture: "basic.html", policy: policy)) {
                guard let error = $0 as? RuleExecutionError, case .invalidXPath = error else {
                    return XCTFail("Unexpected error: \($0)")
                }
            }
        }
    }

    func testXPathRegexTemplateAndVariableComposition() throws {
        XCTAssertEqual(try run(try parser.parse("//h1/text()##Heading##Title"), fixture: "basic.html"), .strings(["Title"]))
        XCTAssertEqual(try run(try parser.parse("value={{//h1/text()}}"), fixture: "basic.html"), .string("value=Heading"))
        let variable = RuleExpression.variableWrite([
            RuleVariableAssignment(key: "heading", value: .xpath("//h1/text()"))
        ], .template(TemplateExpression(parts: [.expression(.variableRead("heading"))])))
        XCTAssertEqual(try run(variable, fixture: "basic.html"), .string("Heading"))
    }

    func testLegadoCombinations() throws {
        XCTAssertEqual(try run(try parser.parse("//ul/li[1]/text()&&//ul/li[last()]/text()"), fixture: "lists.html"), .strings(["Alpha", "Gamma"]))
        XCTAssertEqual(try run(try parser.parse("//missing||//ol/li[1]/text()"), fixture: "lists.html"), .strings(["One"]))
        XCTAssertEqual(try run(try parser.parse("//ul/li[1]/text()%%//ol/li[1]/text()"), fixture: "lists.html"), .strings(["Alpha", "One"]))
    }

    func testJSoupToXPathSequenceUsesOneSelectorExecutor() throws {
        let expression = RuleExpression.sequence([
            .selector(SelectorRule(type: .css, value: "main@all")),
            .xpath("//strong/text()")
        ])
        XCTAssertEqual(try run(expression, fixture: "basic.html"), .strings(["world"]))
    }

    func testStringsInputUsesAndroidListStringRepresentation() throws {
        XCTAssertEqual(try run(.xpath("//b/text()"), input: .strings(["<b>One</b>", "<b>Two</b>"])), .strings(["One", "Two"]))
    }

    func testRepeatedExecutionIsDeterministicAndContextsAreIsolated() throws {
        let expression = try parser.parse("//li/text()")
        XCTAssertEqual(try run(expression, fixture: "lists.html"), try run(expression, fixture: "lists.html"))
        var first = RuleExecutionContext(temporaryVariables: ["scope": "first"])
        var second = RuleExecutionContext(temporaryVariables: ["scope": "second"])
        let input = RuleExecutionInput(.string(try fixture("lists.html")))
        let executor = RuleExecutor(selectorExecutor: LegadoRuleSelectorExecutor())
        _ = try executor.execute(expression, input: input, context: &first)
        _ = try executor.execute(expression, input: input, context: &second)
        XCTAssertEqual(first.variable(named: "scope"), "first")
        XCTAssertEqual(second.variable(named: "scope"), "second")
    }

    private func run(_ path: String, fixture name: String, policy: RuleParseContext.ErrorPolicy = .legadoCompatible) throws -> RuleValue {
        try run(.xpath(path), input: .string(try fixture(name)), policy: policy)
    }

    private func run(_ expression: RuleExpression, fixture name: String) throws -> RuleValue {
        try run(expression, input: .string(try fixture(name)))
    }

    private func run(_ expression: RuleExpression, input: RuleValue, policy: RuleParseContext.ErrorPolicy = .legadoCompatible) throws -> RuleValue {
        var context = RuleExecutionContext(errorPolicy: policy)
        return try RuleExecutor(selectorExecutor: LegadoRuleSelectorExecutor()).execute(
            expression, input: RuleExecutionInput(input), context: &context
        ).value
    }

    private func fixture(_ name: String) throws -> String {
        String(decoding: try FixtureLoader.data(named: name, directory: "rules/xpath"), as: UTF8.self)
    }
}
