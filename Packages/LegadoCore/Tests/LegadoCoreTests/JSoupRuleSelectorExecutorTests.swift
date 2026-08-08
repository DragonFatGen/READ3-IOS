import Foundation
import XCTest
@testable import LegadoCore

final class JSoupRuleSelectorExecutorTests: XCTestCase {
    func testTagShortcutSelector() throws {
        XCTAssertEqual(try execute("tag.h1@text", fixture: "basic.html"), .strings(["阅读 三"]))
    }

    func testClassShortcutSelector() throws {
        XCTAssertEqual(try execute("class.book@text", fixture: "nested.html"),
                       .strings(["Book A Author A", "Book B Author B"]))
    }

    func testIDShortcutSelector() throws {
        XCTAssertEqual(try execute("id.hero@text", fixture: "basic.html"),
                       .strings(["阅读 三 Alpha Beta Omega"]))
    }

    func testDescendantCSSInHistoricalSelectionStage() throws {
        XCTAssertEqual(try execute("section .author@text", fixture: "nested.html"),
                       .strings(["Author A", "Author B"]))
    }

    func testChildCSSInHistoricalSelectionStage() throws {
        XCTAssertEqual(try execute("ul > li@text", fixture: "lists.html"),
                       .strings(["zero", "one", "two", "three", "four"]))
    }

    func testAttributeSelector() throws {
        XCTAssertEqual(try execute("a[data-kind]@text", fixture: "attributes.html"),
                       .strings(["One", "Duplicate URL", "No URL"]))
    }

    func testTextNormalizesDescendantText() throws {
        XCTAssertEqual(try execute("class.summary@text", fixture: "basic.html"),
                       .strings(["Alpha Beta Omega"]))
    }

    func testOwnTextExcludesDescendantText() throws {
        XCTAssertEqual(try execute("class.summary@ownText", fixture: "basic.html"),
                       .strings(["Alpha Omega"]))
    }

    func testTextNodesTrimAndJoinDirectNodes() throws {
        XCTAssertEqual(try execute("class.summary@textNodes", fixture: "basic.html"),
                       .strings(["Alpha\nOmega"]))
    }

    func testHTMLRemovesScriptAndStyleAndReturnsOuterHTML() throws {
        let html = #"<div id="content"><p>safe</p><script>bad()</script><style>.x{}</style></div>"#
        let value = try execute("id.content@html", html: html).stringValue
        XCTAssertTrue(value.contains(#"<div id="content">"#))
        XCTAssertTrue(value.contains("<p>safe</p>"))
        XCTAssertFalse(value.contains("<script"))
        XCTAssertFalse(value.contains("<style"))
    }

    func testAllReturnsOuterHTMLWithoutRemovingChildren() throws {
        let html = #"<div id="content"><script>bad()</script></div>"#
        XCTAssertTrue(try execute("id.content@all", html: html).stringValue.contains("<script>bad()</script>"))
    }

    func testOuterHtmlKeywordIsNotAnAndroidExtractionAlias() throws {
        XCTAssertEqual(try execute("tag.main@outerHtml", fixture: "basic.html"), .none)
    }

    func testHrefReturnsRawRelativeValueAndDeduplicates() throws {
        XCTAssertEqual(try execute("tag.a@href", fixture: "attributes.html"), .strings(["/book/1"]))
    }

    func testSrcReturnsRawRelativeValue() throws {
        XCTAssertEqual(try execute("tag.img@src", fixture: "attributes.html"),
                       .strings(["images/cover.jpg"]))
    }

    func testCustomDataAttribute() throws {
        XCTAssertEqual(try execute("tag.a@data-kind", fixture: "attributes.html"),
                       .strings(["novel", "duplicate", "missing-href"]))
    }

    func testMissingAttributeAndNoMatchAreNone() throws {
        XCTAssertEqual(try execute("tag.img@missing", fixture: "attributes.html"), .none)
        XCTAssertEqual(try execute("tag.unknown@text", fixture: "attributes.html"), .none)
    }

    func testIndexZeroAndOne() throws {
        XCTAssertEqual(try execute("tag.li[0]@text", fixture: "lists.html"), .strings(["zero"]))
        XCTAssertEqual(try execute("tag.li[1]@text", fixture: "lists.html"), .strings(["one"]))
    }

    func testNegativeIndex() throws {
        XCTAssertEqual(try execute("tag.li[-1]@text", fixture: "lists.html"), .strings(["four"]))
    }

    func testInclusiveRange() throws {
        XCTAssertEqual(try execute("tag.li[1:3]@text", fixture: "lists.html"),
                       .strings(["one", "two", "three"]))
    }

    func testMultipleIndexesFollowRuleOrder() throws {
        XCTAssertEqual(try execute("tag.li[4,0,2]@text", fixture: "lists.html"),
                       .strings(["four", "zero", "two"]))
    }

    func testExcludeOneAndMultipleNodes() throws {
        XCTAssertEqual(try execute("tag.li[!1]@text", fixture: "exclude.html"),
                       .strings(["keep-0", "keep-2", "drop-3"]))
        XCTAssertEqual(try execute("tag.li[!1,3]@text", fixture: "exclude.html"),
                       .strings(["keep-0", "keep-2"]))
    }

    func testExcludeMissingIndexKeepsAllAndExcludeAllIsNone() throws {
        XCTAssertEqual(try execute("tag.li[!99]@text", fixture: "exclude.html"),
                       .strings(["keep-0", "drop-1", "keep-2", "drop-3"]))
        XCTAssertEqual(try execute("tag.li[!0:3]@text", fixture: "exclude.html"), .none)
    }

    func testHistoricalAtChainTraversesEachParent() throws {
        XCTAssertEqual(try execute("class.book@tag.h2@text", fixture: "nested.html"),
                       .strings(["Book A", "Book B"]))
    }

    func testDoubleAtForcesHistoricalParsing() throws {
        XCTAssertEqual(try execute("@@tag.h1@text", fixture: "basic.html"), .strings(["阅读 三"]))
    }

    func testExplicitCSSUsesLastAtAsExtractionBoundary() throws {
        XCTAssertEqual(try execute("@CSS:section.shelf > article.book@text", fixture: "nested.html"),
                       .strings(["Book A Author A", "Book B Author B"]))
    }

    func testExplicitCSSWithoutExtractionFailsClearly() throws {
        let html = try fixture("basic.html")
        XCTAssertThrowsError(try execute("@CSS:h1", html: html)) {
            guard let error = $0 as? RuleExecutionError,
                  case .selectorExecutionFailed = error else {
                return XCTFail("Unexpected error: \($0)")
            }
        }
    }

    func testSelectorThenRegexReplacement() throws {
        XCTAssertEqual(try execute("tag.h1@text##阅读##READ", fixture: "basic.html"),
                       .strings(["READ 三"]))
    }

    func testSelectorThenTemplateReadsCurrentResult() throws {
        let selector = try RuleParser().parse("tag.h1@text")
        let template = RuleExpression.template(TemplateExpression(parts: [
            .literal("<"), .expression(.variableRead("result")), .literal(">")
        ]))
        XCTAssertEqual(try execute(.sequence([selector, template]), html: fixture("basic.html")),
                       .string("<阅读 三>"))
    }

    func testSelectorThenVariableWriteUsesCurrentResult() throws {
        let selector = try RuleParser().parse("tag.h1@text")
        let variables = RuleExpression.variableWrite(
            [RuleVariableAssignment(key: "title", value: .variableRead("result"))],
            .variableRead("title")
        )
        var context = RuleExecutionContext()
        XCTAssertEqual(try execute(.sequence([selector, variables]), html: fixture("basic.html"), context: &context),
                       .string("阅读 三"))
        XCTAssertEqual(context.variable(named: "title"), "阅读 三")
    }

    func testEmptyAndMalformedHTMLAreTolerated() throws {
        XCTAssertEqual(try execute("tag.p@text", fixture: "empty.html"), .none)
        XCTAssertEqual(try execute("tag.p@text", html: "<div><p>unfinished"),
                       .strings(["unfinished"]))
    }

    func testUnicodeTextIsPreserved() throws {
        XCTAssertEqual(try execute("tag.p@text", html: "<p>繁體中文 📚 café</p>"),
                       .strings(["繁體中文 📚 café"]))
    }

    func testStringListInputMatchesAndroidListStringificationBoundary() throws {
        let value = try execute("@text", input: .strings(["<p>A</p>", "<p>B</p>"]))
        XCTAssertTrue(value.stringValue.contains("A"))
        XCTAssertTrue(value.stringValue.contains("B"))
    }

    func testRepeatedExecutionIsDeterministicAndContextsStayIsolated() throws {
        let html = try fixture("nested.html")
        var first = RuleExecutionContext(temporaryVariables: ["local": "first"])
        var second = RuleExecutionContext(temporaryVariables: ["local": "second"])
        let expression = try RuleParser().parse("class.author@text")
        let a = try execute(expression, html: html, context: &first)
        let b = try execute(expression, html: html, context: &second)
        XCTAssertEqual(a, b)
        XCTAssertEqual(first.variable(named: "local"), "first")
        XCTAssertEqual(second.variable(named: "local"), "second")
    }

    private func execute(_ rule: String, fixture name: String) throws -> RuleValue {
        try execute(rule, html: fixture(name))
    }

    private func execute(_ rule: String, html: String) throws -> RuleValue {
        try execute(try RuleParser().parse(rule), html: html)
    }

    private func execute(_ rule: String, input: RuleValue) throws -> RuleValue {
        var context = RuleExecutionContext()
        return try RuleExecutor(selectorExecutor: JSoupRuleSelectorExecutor()).execute(
            try RuleParser().parse(rule), input: RuleExecutionInput(input), context: &context
        ).value
    }

    private func execute(_ expression: RuleExpression, html: String) throws -> RuleValue {
        var context = RuleExecutionContext()
        return try execute(expression, html: html, context: &context)
    }

    private func execute(
        _ expression: RuleExpression,
        html: String,
        context: inout RuleExecutionContext
    ) throws -> RuleValue {
        try RuleExecutor(selectorExecutor: JSoupRuleSelectorExecutor()).execute(
            expression, input: RuleExecutionInput(.string(html)), context: &context
        ).value
    }

    private func fixture(_ name: String) throws -> String {
        String(decoding: try FixtureLoader.data(named: name, directory: "rules/jsoup"), as: UTF8.self)
    }
}
