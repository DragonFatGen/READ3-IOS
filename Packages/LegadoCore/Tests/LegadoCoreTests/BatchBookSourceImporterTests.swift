import Foundation
import XCTest
@testable import LegadoCore

final class BatchBookSourceImporterTests: XCTestCase {
    private let importer = BookSourceImporter()

    func testSingleObjectUsesBatchAPIWithoutChangingSingleImport() throws {
        let data = try fixture("batch-single-object.json")
        let single = try importer.importSource(from: data)
        let batch = try importer.importSources(from: data)

        XCTAssertEqual(batch.successes, [single])
        XCTAssertTrue(batch.failures.isEmpty)
    }

    func testImportsTwoModernSourcesInOriginalOrder() throws {
        let result = try importer.importSources(from: fixture("batch-multiple.json"))
        XCTAssertEqual(result.successes.map(\.source.bookSourceName), ["Modern First", "Modern Second"])
        XCTAssertTrue(result.failures.isEmpty)
    }

    func testImportsMixedModernAndLegacySources() throws {
        let result = try importer.importSources(from: fixture("batch-modern-legacy-mixed.json"))
        XCTAssertEqual(result.successes.count, 2)
        XCTAssertEqual(result.successes[1].source.bookSourceType, 1)
    }

    func testEmptyArraySucceedsWithNoResults() throws {
        let result = try importer.importSources(from: fixture("batch-empty.json"))
        XCTAssertTrue(result.successes.isEmpty)
        XCTAssertTrue(result.failures.isEmpty)
    }

    func testStrictModeFailsWholeBatchWithAccurateIndexAndSourceError() throws {
        XCTAssertThrowsError(
            try importer.importSources(from: fixture("batch-invalid-element.json"), mode: .strict)
        ) {
            XCTAssertEqual(
                $0 as? BatchSourceImportError,
                .elementFailed(index: 1, error: .topLevelMustBeObject)
            )
        }
    }

    func testLenientModeContinuesAndReportsSuccessesAndFailure() throws {
        let result = try importer.importSources(
            from: fixture("batch-invalid-element.json"),
            mode: .lenient
        )
        XCTAssertEqual(result.successes.map(\.source.bookSourceName), ["Valid Before", "Valid After"])
        XCTAssertEqual(
            result.failures,
            [BatchSourceImportFailure(index: 1, error: .topLevelMustBeObject)]
        )
    }

    func testWarningsDoNotLeakBetweenSources() throws {
        let data = Data(#"[{"bookSourceUrl":"https://warning.example.invalid","weight":"7"},{"bookSourceUrl":"https://clean.example.invalid"}]"#.utf8)
        let result = try importer.importSources(from: data)
        XCTAssertFalse(result.successes[0].warnings.isEmpty)
        XCTAssertTrue(result.successes[1].warnings.isEmpty)
    }

    func testMigrationsDoNotLeakBetweenSources() throws {
        let result = try importer.importSources(from: fixture("batch-modern-legacy-mixed.json"))
        XCTAssertTrue(result.successes[0].migrations.isEmpty)
        XCTAssertFalse(result.successes[1].migrations.isEmpty)
    }

    func testExtraFieldsDoNotLeakBetweenSources() throws {
        let result = try importer.importSources(from: fixture("batch-multiple.json"))
        XCTAssertEqual(result.successes[0].source.extraFields["firstExtra"], .bool(true))
        XCTAssertNil(result.successes[0].source.extraFields["secondExtra"])
        XCTAssertEqual(result.successes[1].source.extraFields["secondExtra"], .integer(2))
        XCTAssertNil(result.successes[1].source.extraFields["firstExtra"])
    }

    func testTopLevelStringIsRejected() throws {
        XCTAssertThrowsError(try importer.importSources(from: fixture("batch-invalid-top-level.json"))) {
            XCTAssertEqual($0 as? SourceImportError, .topLevelMustBeObjectOrArray)
        }
    }

    func testTopLevelNumberIsRejected() {
        XCTAssertThrowsError(try importer.importSources(from: Data("123".utf8))) {
            XCTAssertEqual($0 as? SourceImportError, .topLevelMustBeObjectOrArray)
        }
    }

    func testTopLevelBooleanAndNullAreRejected() {
        for value in ["true", "null"] {
            XCTAssertThrowsError(try importer.importSources(from: Data(value.utf8))) {
                XCTAssertEqual($0 as? SourceImportError, .topLevelMustBeObjectOrArray)
            }
        }
    }

    func testRepeatedBatchImportsAreStable() throws {
        let data = try fixture("batch-modern-legacy-mixed.json")
        let first = try importer.importSources(from: data)
        let second = try importer.importSources(from: data)
        XCTAssertEqual(first, second)
    }

    private func fixture(_ name: String) throws -> Data {
        try FixtureLoader.data(named: name, directory: "book-source-import")
    }
}
