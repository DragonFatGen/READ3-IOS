import Foundation
import XCTest
@testable import LegadoCore

final class BookSourceBatchImporterTests: XCTestCase {
    private let importer = BookSourceImporter()

    func testTopLevelObjectMatchesSingleSourceAPI() throws {
        let data = try fixture("batch-single-object.json")

        let single = try importer.importSource(from: data)
        let batch = try importer.importSources(from: data)

        XCTAssertEqual(batch, [single])
    }

    func testArrayOrderAndExtraFieldsRemainPerSource() throws {
        let results = try importer.importSources(
            from: fixture("batch-multiple-sources.json")
        )

        XCTAssertEqual(results.map(\.source.bookSourceName), ["First", "Second", "Third"])
        XCTAssertEqual(results.map { $0.source.extraFields["sourceOnly"] }, [
            .string("first"), .string("second"), .string("third")
        ])
    }

    func testEmptyArrayReturnsNoResultsOrFailures() throws {
        let strict = try importer.importSources(from: fixture("batch-empty-array.json"))
        let lenient = try importer.importSources(
            from: fixture("batch-empty-array.json"),
            policy: .lenient
        )

        XCTAssertTrue(strict.isEmpty)
        XCTAssertTrue(lenient.results.isEmpty)
        XCTAssertTrue(lenient.failures.isEmpty)
    }

    func testStrictModeThrowsIndexedSourceImportError() throws {
        XCTAssertThrowsError(
            try importer.importSources(from: fixture("batch-invalid-element.json"))
        ) { error in
            XCTAssertEqual(
                error as? SourceBatchImportError,
                SourceBatchImportError(index: 1, sourceError: .topLevelMustBeObject)
            )
        }
    }

    func testLenientModeKeepsSuccessesAndRecordsExactFailureIndex() throws {
        let batch = try importer.importSources(
            from: fixture("batch-invalid-element.json"),
            policy: .lenient
        )

        XCTAssertEqual(
            batch.results.map(\.source.bookSourceName),
            ["Valid First", "Valid Last"]
        )
        XCTAssertEqual(batch.failures.count, 1)
        XCTAssertEqual(batch.failures[0].index, 1)
        XCTAssertEqual(batch.failures[0].underlyingError, .topLevelMustBeObject)
    }

    func testWarningsAndMigrationsAreIndependentForMixedSources() throws {
        let results = try importer.importSources(
            from: fixture("batch-modern-legacy-mixed.json")
        )

        XCTAssertTrue(results[0].warnings.isEmpty)
        XCTAssertTrue(results[0].migrations.isEmpty)
        XCTAssertNil(results[0].source.extraFields["legacyOnly"])
        XCTAssertEqual(results[0].source.extraFields["modernOnly"], .bool(true))

        XCTAssertEqual(results[1].source.bookSourceType, 1)
        XCTAssertEqual(results[1].source.ruleSearch?.name, ".legacy-name@text")
        XCTAssertFalse(results[1].warnings.isEmpty)
        XCTAssertFalse(results[1].migrations.isEmpty)
        XCTAssertNil(results[1].source.extraFields["modernOnly"])
        XCTAssertEqual(results[1].source.extraFields["legacyOnly"], .bool(true))
    }

    func testBatchNormalizationIsStablePerItem() throws {
        let first = try importer.importSources(
            from: fixture("batch-modern-legacy-mixed.json")
        )

        for result in first {
            let second = try importer.importSource(from: result.normalizedJSON)
            XCTAssertEqual(second.normalizedJSON, result.normalizedJSON)
            XCTAssertTrue(second.warnings.isEmpty)
            XCTAssertTrue(second.migrations.isEmpty)
        }
    }

    func testScalarTopLevelsRemainTypedImportErrors() throws {
        for name in ["batch-top-level-string.json", "batch-top-level-number.json"] {
            XCTAssertThrowsError(try importer.importSources(from: fixture(name))) { error in
                XCTAssertEqual(error as? SourceImportError, .topLevelMustBeObject)
            }
        }
    }

    private func fixture(_ name: String) throws -> Data {
        try FixtureLoader.data(named: name, directory: "book-source-import")
    }
}
