import Foundation
import XCTest
@testable import LegadoCore

final class BookSourceImporterTests: XCTestCase {
    private let importer = BookSourceImporter()
    private let decoder = JSONDecoder()

    func testMigratesLegacySearchRulesAndURL() throws {
        let result = try importFixture("legacy-search-rule.json")
        XCTAssertEqual(result.source.ruleSearch?.bookList, ".book||.result")
        XCTAssertEqual(result.source.ruleSearch?.name, ".name@text")
        XCTAssertEqual(
            result.source.searchUrl,
            "https://legacy-search.example.invalid/search?key={{key}}&pg={{page}}"
        )
        XCTAssertTrue(result.migrations.contains { $0.destinationField == "ruleSearch" })
    }

    func testMigratesLegacyExploreRulesAndMultipleURLs() throws {
        let result = try importFixture("legacy-explore-rule.json")
        XCTAssertEqual(result.source.ruleExplore?.bookList, ".book")
        XCTAssertTrue(result.source.exploreUrl?.contains("\n") == true)
        XCTAssertTrue(result.migrations.contains { $0.destinationField == "ruleExplore" })
    }

    func testMigratesLegacyBookInfoRules() throws {
        let result = try importFixture("legacy-book-info-rule.json")
        XCTAssertEqual(result.source.ruleBookInfo?.`init`, "##detail")
        XCTAssertEqual(result.source.ruleBookInfo?.tocUrl, ".toc@href")
    }

    func testMigratesLegacyTOCRules() throws {
        let result = try importFixture("legacy-toc-rule.json")
        XCTAssertEqual(result.source.ruleToc?.chapterList, ".chapter")
        XCTAssertEqual(result.source.ruleToc?.nextTocUrl, ".next@href")
    }

    func testMigratesLegacyContentRules() throws {
        let result = try importFixture("legacy-content-rule.json")
        XCTAssertEqual(result.source.ruleContent?.content, "content@html")
        XCTAssertEqual(result.source.ruleContent?.replaceRegex, "##advertisement##")
        XCTAssertEqual(result.source.ruleContent?.nextContentUrl, ".next@href")
    }

    func testDecodesEveryStringRuleObject() throws {
        let result = try importFixture("string-rule-object.json")
        XCTAssertEqual(result.source.ruleSearch?.name, "$.name")
        XCTAssertEqual(result.source.ruleExplore?.bookList, "$.categories[*]")
        XCTAssertEqual(result.source.ruleBookInfo?.name, "$.book.name")
        XCTAssertEqual(result.source.ruleToc?.chapterList, "$.chapters[*]")
        XCTAssertEqual(result.source.ruleContent?.content, "$.content")
        XCTAssertEqual(result.migrations.filter { $0.kind == .stringRuleObject }.count, 5)
    }

    func testConvertsLegacyAudioType() throws {
        let result = try importFixture("legacy-audio-source.json")
        XCTAssertEqual(result.source.bookSourceType, 1)
        XCTAssertTrue(result.migrations.contains { $0.kind == .legacySourceType })
    }

    func testAcceptsLoginURLStringWithoutMigration() throws {
        let result = try importFixture("login-url-string.json")
        XCTAssertEqual(result.source.loginUrl, "https://login-string.example.invalid/login")
        XCTAssertTrue(result.migrations.isEmpty)
    }

    func testExtractsLoginURLObjectAndPreservesExtraMembers() throws {
        let result = try importFixture("login-url-object.json")
        XCTAssertEqual(result.source.loginUrl, "https://login-object.example.invalid/login")
        XCTAssertNotNil(result.source.extraFields["legacyLoginUrl"])
        XCTAssertTrue(result.warnings.contains { $0.code == .unsupportedLegacyValuePreserved })
    }

    func testPreservesLoginURLArrayAsJSONString() throws {
        let result = try importFixture("login-url-array.json")
        XCTAssertTrue(result.source.loginUrl?.contains("first") == true)
        XCTAssertTrue(result.source.loginUrl?.contains("second") == true)
        XCTAssertTrue(result.warnings.contains { $0.code == .androidBehaviorDifference })
    }

    func testEmptyLegacyExploreURLDisablesExplore() throws {
        let result = try importFixture("empty-explore-url.json")
        XCTAssertNil(result.source.exploreUrl)
        XCTAssertFalse(result.source.enabledExplore)
        XCTAssertTrue(result.migrations.contains { $0.kind == .emptyExploreURL })
    }

    func testCoercesNumericRepresentations() throws {
        let result = try importFixture("numeric-coercion.json")
        XCTAssertEqual(result.source.bookSourceType, 1)
        XCTAssertEqual(result.source.customOrder, 42)
        XCTAssertEqual(result.source.lastUpdateTime, 1_700_000_000_000)
        XCTAssertEqual(result.source.respondTime, 2_500)
        XCTAssertEqual(result.source.weight, -7)
        XCTAssertEqual(result.warnings.filter { $0.code == .numericValueCoerced }.count, 5)
    }

    func testModernFieldsWinConflictsAndLegacyDuplicatesAreRemoved() throws {
        let result = try importFixture("modern-legacy-conflict.json")
        XCTAssertEqual(result.source.searchUrl, "https://conflict.example.invalid/modern")
        XCTAssertEqual(result.source.ruleSearch?.bookList, ".modern")
        XCTAssertGreaterThanOrEqual(
            result.warnings.filter { $0.code == .modernFieldWonConflict }.count,
            2
        )
        let object = try normalizedObject(result)
        XCTAssertNil(object["ruleSearchUrl"])
        XCTAssertNil(object["ruleSearchList"])
        XCTAssertNil(object["ruleSearchName"])
    }

    func testUnsupportedLegacyValueAndUnknownFieldArePreserved() throws {
        let result = try importFixture("unsupported-legacy-value.json")
        XCTAssertEqual(
            result.source.extraFields["ruleSearchName"],
            .object(["selector": .string(".name")])
        )
        XCTAssertEqual(
            result.source.extraFields["futureImportMetadata"],
            .object(["version": .integer(9)])
        )
        XCTAssertTrue(result.warnings.contains { $0.field == "ruleSearchName" })
    }

    func testAlreadyModernSourceHasNoMigrationAndPreservesUnknownField() throws {
        let result = try importFixture("already-modern-source.json")
        XCTAssertTrue(result.warnings.isEmpty)
        XCTAssertTrue(result.migrations.isEmpty)
        XCTAssertEqual(result.source.extraFields["futureField"], .object(["keep": .bool(true)]))
    }

    func testNormalizationIsIdempotent() throws {
        for name in [
            "legacy-search-rule.json", "string-rule-object.json", "legacy-audio-source.json",
            "login-url-object.json", "numeric-coercion.json", "already-modern-source.json"
        ] {
            let first = try importFixture(name)
            let second = try importer.importSource(from: first.normalizedJSON)
            XCTAssertEqual(second.normalizedJSON, first.normalizedJSON, name)
            XCTAssertTrue(second.migrations.isEmpty, name)
            XCTAssertTrue(second.warnings.isEmpty, name)
        }
    }

    func testNormalizedLegacySourceContainsNoSafelyMigratedRootDuplicates() throws {
        let result = try importer.importSource(from: FixtureLoader.data(named: "legacy.json"))
        let object = try normalizedObject(result)
        for key in [
            "ruleBookUrlPattern", "serialNumber", "enable", "httpUserAgent",
            "ruleSearchUrl", "ruleFindUrl", "ruleSearchList", "ruleFindList",
            "ruleBookInfoInit", "ruleChapterList", "ruleBookContent"
        ] {
            XCTAssertNil(object[key], key)
        }
        XCTAssertNotNil(object["ruleSearch"])
        XCTAssertNotNil(object["ruleExplore"])
        XCTAssertNotNil(object["ruleBookInfo"])
        XCTAssertNotNil(object["ruleToc"])
        XCTAssertNotNil(object["ruleContent"])
    }

    func testInvalidJSONThrowsImportError() {
        XCTAssertThrowsError(try importer.importSource(from: Data("{".utf8))) {
            XCTAssertEqual($0 as? SourceImportError, .invalidJSON)
        }
    }

    func testTopLevelArrayThrowsImportError() {
        XCTAssertThrowsError(try importer.importSource(from: Data("[]".utf8))) {
            XCTAssertEqual($0 as? SourceImportError, .topLevelMustBeObject)
        }
    }

    func testInvalidRuleJSONStringThrowsImportError() {
        let data = Data(#"{"bookSourceUrl":"https://bad-rule.example.invalid","ruleToc":"not-json"}"#.utf8)
        XCTAssertThrowsError(try importer.importSource(from: data)) {
            XCTAssertEqual($0 as? SourceImportError, .invalidRuleJSONString(field: "ruleToc"))
        }
    }

    func testNumericBoundaries() throws {
        let valid = Data(#"{"bookSourceUrl":"https://boundary.example.invalid","weight":"2147483647","lastUpdateTime":"9223372036854775807"}"#.utf8)
        let result = try importer.importSource(from: valid)
        XCTAssertEqual(result.source.weight, Int(Int32.max))
        XCTAssertEqual(result.source.lastUpdateTime, Int64.max)

        let invalid = Data(#"{"bookSourceUrl":"https://boundary.example.invalid","weight":2147483648}"#.utf8)
        XCTAssertThrowsError(try importer.importSource(from: invalid)) {
            XCTAssertEqual(
                $0 as? SourceImportError,
                .invalidField(field: "weight", expected: "a 32-bit integer-compatible number")
            )
        }
    }

    func testLegacyScalarFieldsMigrateAndConflictSafely() throws {
        let data = Data(#"""
        {
          "bookSourceUrl":"https://scalar.example.invalid",
          "bookUrlPattern":"modern",
          "ruleBookUrlPattern":"legacy",
          "serialNumber":8,
          "enable":false,
          "httpUserAgent":"Fixture Agent"
        }
        """#.utf8)
        let result = try importer.importSource(from: data)
        XCTAssertEqual(result.source.bookUrlPattern, "modern")
        XCTAssertEqual(result.source.customOrder, 8)
        XCTAssertFalse(result.source.enabled)
        XCTAssertEqual(result.source.header, #"{"User-Agent":"Fixture Agent"}"#)
        XCTAssertTrue(result.warnings.contains { $0.field == "bookUrlPattern" })
    }

    private func importFixture(_ name: String) throws -> SourceImportResult {
        try importer.importSource(
            from: FixtureLoader.data(named: name, directory: "book-source-import")
        )
    }

    private func normalizedObject(_ result: SourceImportResult) throws -> [String: JSONValue] {
        let value = try decoder.decode(JSONValue.self, from: result.normalizedJSON)
        guard case let .object(object) = value else {
            XCTFail("Expected normalized object")
            return [:]
        }
        return object
    }
}
