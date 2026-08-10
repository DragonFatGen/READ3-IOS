import Foundation
import XCTest
@testable import LegadoCore

final class RuleNodeContextTests: XCTestCase {
    func testHTMLBookListReturnsTwoNodes() throws {
        XCTAssertEqual(try nodes("class.book", fixture: "html-multiple.html").count, 2)
    }

    func testHTMLNamesStayRelativeToEachItem() throws {
        let items = try nodes("class.book", fixture: "html-multiple.html").nodes
        XCTAssertEqual(try values("tag.h2@text", items), ["A", "B"])
    }

    func testHTMLAuthorsStayRelativeToEachItem() throws {
        let items = try nodes("class.book", fixture: "html-multiple.html").nodes
        XCTAssertEqual(try values("class.author@text", items), ["AA", "BB"])
    }

    func testHTMLNestedSelectorUsesItemRoot() throws {
        let items = try nodes("class.book", fixture: "html-multiple.html").nodes
        XCTAssertEqual(try values("tag.a@tag.h2@text", items), ["A", "B"])
    }

    func testHTMLAttributeUsesItemRoot() throws {
        let items = try nodes("class.book", fixture: "html-multiple.html").nodes
        XCTAssertEqual(try values("tag.a@href", items), ["/a", "/b"])
    }

    func testJSoupNodeSupportsRelativeXPath() throws {
        let items = try nodes("class.book", fixture: "html-multiple.html").nodes
        XCTAssertEqual(try values("@XPath:.//h2/text()", items), ["A", "B"])
    }

    func testExplicitCSSProducesHTMLNodes() throws {
        let collection = try nodes("@CSS:.book", fixture: "html-multiple.html")
        XCTAssertEqual(collection.nodes.map(\.kind), [.html, .html])
    }

    func testJSONBookListReturnsTwoObjectNodes() throws {
        let collection = try nodes("$.items[*]", fixture: "json-multiple.json")
        XCTAssertEqual(collection.count, 2)
        XCTAssertEqual(collection.nodes.map(\.kind), [.json, .json])
    }

    func testJSONNameStaysRelativeToObject() throws {
        let items = try nodes("$.items[*]", fixture: "json-multiple.json").nodes
        XCTAssertEqual(try values("$.name", items), ["A", "B"])
    }

    func testJSONAuthorStaysRelativeToObject() throws {
        let items = try nodes("$.items[*]", fixture: "json-multiple.json").nodes
        XCTAssertEqual(try values("$.author", items), ["AA", "BB"])
    }

    func testJSONNestedObjectStaysRelative() throws {
        let item = try XCTUnwrap(nodes("$.items[*]", fixture: "json-basic.json").nodes.first)
        XCTAssertEqual(try value("$.meta.kind", item), "Fantasy")
    }

    func testJSONArrayFieldStaysRelative() throws {
        let item = try XCTUnwrap(nodes("$.items[*]", fixture: "json-basic.json").nodes.first)
        XCTAssertEqual(try value("$.tags[*]", item), "one\ntwo")
    }

    func testXPathBookListReturnsElementNodes() throws {
        let collection = try nodes("@XPath://article", fixture: "xpath-basic.html")
        XCTAssertEqual(collection.count, 2)
        XCTAssertEqual(collection.nodes.map(\.kind), [.html, .html])
    }

    func testXPathFieldsStayRelative() throws {
        let items = try nodes("@XPath://article", fixture: "xpath-basic.html").nodes
        XCTAssertEqual(try values("@XPath:.//span[@class='author']/text()", items), ["XA", "XB"])
    }

    func testNodeIdentitySurvivesMultipleFieldExecutions() throws {
        let item = try XCTUnwrap(nodes("class.book", fixture: "html-basic.html").nodes.first)
        let copy = item
        XCTAssertEqual(try value("tag.h2@text", item), "Book A")
        XCTAssertEqual(try value("class.author@text", item), "Author A")
        XCTAssertEqual(item, copy)
    }

    func testJavaScriptDirectStructuredInputIsExplicitlyUnsupported() throws {
        let item = try XCTUnwrap(nodes("class.book", fixture: "html-basic.html").nodes.first)
        var context = RuleExecutionContext()
        XCTAssertThrowsError(try RuleExecutor(selectorExecutor: LegadoRuleSelectorExecutor()).execute(
            .javaScript("result"), input: RuleExecutionInput(node: item), context: &context
        )) { error in
            XCTAssertEqual(error as? RuleExecutionError, .unsupportedExecutionNode("JavaScript structured input"))
        }
    }

    private func nodes(_ rule: String, fixture name: String) throws -> RuleNodeCollection {
        let body = String(decoding: try FixtureLoader.data(named: name, directory: "search"), as: UTF8.self)
        var context = RuleExecutionContext()
        return try RuleNodeExecutor(selectorExecutor: LegadoRuleSelectorExecutor()).execute(
            RuleParser().parse(rule, context: RuleParseContext(contentIsJSON: name.hasSuffix(".json"))),
            input: RuleExecutionInput(.string(body)),
            context: &context
        )
    }

    private func values(_ rule: String, _ nodes: [RuleNode]) throws -> [String] {
        try nodes.map { try value(rule, $0) }
    }

    private func value(_ rule: String, _ node: RuleNode) throws -> String {
        var context = RuleExecutionContext()
        return try RuleExecutor(selectorExecutor: LegadoRuleSelectorExecutor()).execute(
            RuleParser().parse(rule, context: RuleParseContext(contentIsJSON: node.kind == .json)),
            input: RuleExecutionInput(node: node),
            context: &context
        ).value.stringValue
    }
}
