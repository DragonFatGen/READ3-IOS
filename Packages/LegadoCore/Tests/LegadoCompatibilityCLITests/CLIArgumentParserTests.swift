import XCTest
@testable import LegadoCompatibilityCLI

final class CLIArgumentParserTests: XCTestCase {
    private let parser = CLIArgumentParser()

    func testParsesAllOptions() throws {
        let parsed = try options([
            "--source", "source.json",
            "--keyword", "三体",
            "--search-page", "2",
            "--book-index", "3",
            "--chapter-index", "4",
            "--maximum-page-count", "25",
            "--json"
        ])
        XCTAssertEqual(parsed.sourcePath, "source.json")
        XCTAssertEqual(parsed.keyword, "三体")
        XCTAssertEqual(parsed.searchPage, 2)
        XCTAssertEqual(parsed.bookIndex, 3)
        XCTAssertEqual(parsed.chapterIndex, 4)
        XCTAssertEqual(parsed.maximumPageCount, 25)
        XCTAssertTrue(parsed.usesJSONOutput)
    }

    func testDefaultValues() throws {
        let parsed = try options(["--source", "source.json", "--keyword", "书"])
        XCTAssertEqual(parsed.searchPage, 1)
        XCTAssertEqual(parsed.bookIndex, 0)
        XCTAssertEqual(parsed.chapterIndex, 0)
        XCTAssertEqual(parsed.maximumPageCount, 100)
        XCTAssertFalse(parsed.usesJSONOutput)
    }

    func testHelpDoesNotRequireOtherArguments() throws {
        XCTAssertEqual(try parser.parse(["--help"]), .help)
    }

    func testMissingRequiredArgumentsFail() {
        XCTAssertThrowsError(try parser.parse(["--keyword", "书"])) {
            XCTAssertEqual($0 as? CLIArgumentError, .missingRequiredOption("--source"))
        }
        XCTAssertThrowsError(try parser.parse(["--source", "source.json"])) {
            XCTAssertEqual($0 as? CLIArgumentError, .missingRequiredOption("--keyword"))
        }
    }

    func testUnknownArgumentFails() {
        XCTAssertThrowsError(try parser.parse([
            "--source", "source.json", "--keyword", "书", "--live"
        ])) {
            XCTAssertEqual($0 as? CLIArgumentError, .unknownArgument("--live"))
        }
    }

    func testInvalidAndOutOfRangeNumbersFail() {
        XCTAssertThrowsError(try parser.parse([
            "--source", "source.json", "--keyword", "书", "--book-index", "one"
        ])) {
            XCTAssertEqual(
                $0 as? CLIArgumentError,
                .invalidInteger(option: "--book-index", value: "one")
            )
        }
        XCTAssertThrowsError(try parser.parse([
            "--source", "source.json", "--keyword", "书", "--chapter-index", "-1"
        ]))
        XCTAssertThrowsError(try parser.parse([
            "--source", "source.json", "--keyword", "书", "--search-page", "0"
        ]))
        XCTAssertThrowsError(try parser.parse([
            "--source", "source.json", "--keyword", "书", "--maximum-page-count", "501"
        ]))
    }

    private func options(_ arguments: [String]) throws -> CLIOptions {
        guard case let .options(options) = try parser.parse(arguments) else {
            throw UnexpectedParserResult.help
        }
        return options
    }
}

private enum UnexpectedParserResult: Error { case help }
