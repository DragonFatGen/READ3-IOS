import Foundation
import XCTest
@testable import LegadoCore

final class JSONValueTests: XCTestCase {
    private let decoder = JSONDecoder()
    private let encoder = JSONEncoder()

    func testAllDynamicJSONValueKindsDecode() throws {
        let source = try decoder.decode(
            BookSource.self,
            from: FixtureLoader.data(named: "nested-json.json")
        )

        XCTAssertEqual(source.extraFields["dynamicNull"], .null)
        XCTAssertEqual(source.extraFields["dynamicBool"], .bool(true))
        XCTAssertEqual(source.extraFields["dynamicInteger"], .integer(42))
        XCTAssertEqual(source.extraFields["dynamicNumber"], .number(3.25))
        XCTAssertEqual(source.extraFields["dynamicString"], .string("value"))
        XCTAssertEqual(
            source.extraFields["dynamicArray"],
            .array([.bool(false), .integer(8), .number(1.5), .string("item"), .null])
        )
        XCTAssertNotNil(source.extraFields["dynamicObject"])
    }

    func testJSONValueRoundTrip() throws {
        let original: JSONValue = .object([
            "null": .null,
            "bool": .bool(false),
            "integer": .integer(9),
            "number": .number(4.5),
            "string": .string("text"),
            "array": .array([.integer(1), .object(["nested": .bool(true)])])
        ])

        let decoded = try decoder.decode(JSONValue.self, from: encoder.encode(original))

        XCTAssertEqual(decoded, original)
    }
}
