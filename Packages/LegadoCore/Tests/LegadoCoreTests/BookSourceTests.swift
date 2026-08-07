import Foundation
import XCTest
@testable import LegadoCore

final class BookSourceTests: XCTestCase {
    private let decoder = JSONDecoder()
    private let encoder = JSONEncoder()

    func testMinimalSourceDecodesWithAndroidEntityDefaults() throws {
        let source = try decodeFixture("minimal.json")

        XCTAssertEqual(source.bookSourceUrl, "https://minimal.example.invalid")
        XCTAssertEqual(source.bookSourceName, "Minimal Source")
        XCTAssertEqual(source.bookSourceType, 0)
        XCTAssertEqual(source.customOrder, 0)
        XCTAssertTrue(source.enabled)
        XCTAssertTrue(source.enabledExplore)
        XCTAssertEqual(source.lastUpdateTime, 0)
        XCTAssertEqual(source.respondTime, 180_000)
        XCTAssertEqual(source.weight, 0)
        XCTAssertNil(source.bookSourceGroup)
        XCTAssertNil(source.ruleSearch)
    }

    func testCompleteSourceDecodesTypedFieldsAndJSONNames() throws {
        let source = try decodeFixture("complete.json")

        XCTAssertEqual(source.bookSourceType, 2)
        XCTAssertEqual(source.customOrder, 12)
        XCTAssertFalse(source.enabled)
        XCTAssertEqual(source.concurrentRate, "3/1000")
        XCTAssertEqual(source.lastUpdateTime, 1_700_000_000_000)
        XCTAssertEqual(source.respondTime, 2_500)
        XCTAssertEqual(source.ruleSearch?.checkKeyWord, "{{key}}")
        XCTAssertEqual(source.ruleExplore?.wordCount, ".words@text")
        XCTAssertEqual(source.ruleBookInfo?.`init`, "#book")
        XCTAssertEqual(source.ruleBookInfo?.canReName, "true")
        XCTAssertEqual(source.ruleToc?.nextTocUrl, ".next@href")
        XCTAssertEqual(source.ruleContent?.imageStyle, "FULL")
    }

    func testMissingOptionalAndNullFieldsAreAccepted() throws {
        let source = try decodeFixture("missing-optionals.json")

        XCTAssertNil(source.bookSourceGroup)
        XCTAssertNil(source.header)
        XCTAssertNil(source.loginUrl)
        XCTAssertNil(source.ruleSearch)
        XCTAssertNil(source.ruleToc)
        XCTAssertEqual(source.respondTime, 180_000)
    }

    func testEmptyRuleObjectDecodes() throws {
        let source = try decodeFixture("rules.json")

        XCTAssertEqual(source.ruleExplore, ExploreRule())
        XCTAssertEqual(source.ruleSearch?.bookList, "$.results[*]")
        XCTAssertEqual(source.ruleBookInfo?.tocUrl, "$.book.toc")
        XCTAssertEqual(source.ruleToc?.chapterName, "$.title")
        XCTAssertEqual(source.ruleContent?.content, "$.content")
    }

    func testUnknownFieldsArePreservedAtEveryModelLevel() throws {
        let source = try decodeFixture("unknown-fields.json")

        XCTAssertEqual(source.extraFields["futureMode"], .string("preserve-me"))
        XCTAssertNotNil(source.extraFields["futureConfiguration"])
        XCTAssertEqual(
            source.ruleSearch?.extraFields["futureSelectorMode"],
            .object(["strict": .bool(false)])
        )

        let roundTripped = try decoder.decode(BookSource.self, from: encoder.encode(source))
        XCTAssertEqual(roundTripped, source)
    }

    func testKnownFieldsOverrideConflictingExtraFields() throws {
        let source = BookSource(
            bookSourceUrl: "https://known.example.invalid",
            bookSourceName: "Known Name",
            extraFields: [
                "bookSourceName": .string("Unknown Name"),
                "future": .bool(true)
            ]
        )

        let encoded = try encoder.encode(source)
        let decoded = try decoder.decode(BookSource.self, from: encoded)

        XCTAssertEqual(decoded.bookSourceName, "Known Name")
        XCTAssertNil(decoded.extraFields["bookSourceName"])
        XCTAssertEqual(decoded.extraFields["future"], .bool(true))
    }

    func testDecodeEncodeDecodePreservesCompleteSource() throws {
        let source = try decodeFixture("complete.json")
        let encoded = try encoder.encode(source)
        let decodedAgain = try decoder.decode(BookSource.self, from: encoded)

        XCTAssertEqual(decodedAgain, source)
    }

    func testBookSourceCodableDoesNotPerformLegacyMigration() {
        XCTAssertThrowsError(try decodeFixture("legacy.json"))
    }

    func testImporterMapsLegacyRootFieldsAndRemovesMigratedDuplicates() throws {
        let result = try BookSourceImporter().importSource(from: FixtureLoader.data(named: "legacy.json"))
        let source = result.source

        XCTAssertEqual(source.bookSourceType, 1)
        XCTAssertEqual(source.bookUrlPattern, "^/legacy/book/")
        XCTAssertEqual(source.customOrder, 7)
        XCTAssertFalse(source.enabled)
        XCTAssertTrue(source.enabledExplore)
        XCTAssertEqual(source.header, "{\"User-Agent\":\"Legacy Fixture Agent\"}")
        XCTAssertEqual(source.searchUrl, "https://legacy.example.invalid/search?key={{key}}")
        XCTAssertEqual(source.ruleSearch?.name, ".title@text")
        XCTAssertEqual(source.ruleExplore?.bookList, ".explore-book")
        XCTAssertEqual(source.ruleBookInfo?.tocUrl, ".toc@href")
        XCTAssertEqual(source.ruleToc?.chapterUrl, "a@href")
        XCTAssertEqual(source.ruleContent?.replaceRegex, "##legacy-ad##")
        XCTAssertNil(source.extraFields["ruleSearchName"])

        let encoded = try encoder.encode(source)
        let encodedObject = try decoder.decode(JSONValue.self, from: encoded)
        guard case let .object(fields) = encodedObject else {
            return XCTFail("Expected encoded object")
        }
        XCTAssertNil(fields["ruleSearchName"])
        XCTAssertNotNil(fields["ruleSearch"])
    }

    func testImporterNormalizesCompatibleLoginAndRuleRepresentations() throws {
        let data = Data(#"""
        {
          "bookSourceUrl": "https://compatible.example.invalid",
          "loginUrl": {"url": "https://compatible.example.invalid/login"},
          "loginUi": [{"name": "nickname", "type": "text"}],
          "ruleToc": "{\"chapterList\":\".chapter\"}"
        }
        """#.utf8)

        let source = try BookSourceImporter().importSource(from: data).source

        XCTAssertEqual(source.loginUrl, "https://compatible.example.invalid/login")
        XCTAssertTrue(source.loginUi?.contains("nickname") == true)
        XCTAssertEqual(source.ruleToc?.chapterList, ".chapter")
    }

    func testWrongKnownFieldTypeThrows() {
        let data = Data(#"{"bookSourceUrl":"https://invalid.example.invalid","bookSourceType":{}}"#.utf8)

        XCTAssertThrowsError(try decoder.decode(BookSource.self, from: data))
    }

    func testEncodingDoesNotDropCriticalFields() throws {
        let source = try decodeFixture("complete.json")
        let encoded = try encoder.encode(source)
        let json = try decoder.decode(JSONValue.self, from: encoded)
        guard case let .object(fields) = json else {
            return XCTFail("Expected encoded object")
        }

        XCTAssertEqual(fields["bookSourceUrl"], .string("https://complete.example.invalid"))
        XCTAssertEqual(fields["bookSourceType"], .integer(2))
        XCTAssertNotNil(fields["ruleSearch"])
        XCTAssertNotNil(fields["ruleBookInfo"])
        XCTAssertNotNil(fields["ruleToc"])
        XCTAssertNotNil(fields["ruleContent"])
    }

    private func decodeFixture(_ name: String) throws -> BookSource {
        try decoder.decode(BookSource.self, from: FixtureLoader.data(named: name))
    }
}
