import Foundation

struct CLIOptions: Equatable {
    static let defaultMaximumPageCount = 100
    static let maximumAllowedPageCount = 500

    let sourcePath: String
    let keyword: String
    let searchPage: Int
    let bookIndex: Int
    let chapterIndex: Int
    let maximumPageCount: Int
    let usesJSONOutput: Bool
}

enum CLIArgumentResult: Equatable {
    case options(CLIOptions)
    case help
}

enum CLIArgumentError: Error, Equatable, LocalizedError {
    case missingValue(String)
    case duplicateOption(String)
    case missingRequiredOption(String)
    case invalidInteger(option: String, value: String)
    case outOfRange(option: String, description: String)
    case unknownArgument(String)

    var errorDescription: String? {
        switch self {
        case let .missingValue(option): "Missing value for \(option)."
        case let .duplicateOption(option): "Option \(option) may only be supplied once."
        case let .missingRequiredOption(option): "Required option \(option) is missing."
        case let .invalidInteger(option, value): "Invalid integer for \(option): \(value)."
        case let .outOfRange(option, description): "Invalid \(option): \(description)."
        case let .unknownArgument(argument): "Unknown argument: \(argument)."
        }
    }
}

struct CLIArgumentParser {
    static let help = """
    Usage:
      legado-compatibility --source <path> --keyword <text> [options]

    Required:
      --source <path>                 Local Legado book-source JSON file
      --keyword <text>                Search keyword

    Options:
      --search-page <number>          Search page, default 1 (minimum 1)
      --book-index <number>           Search-result index, default 0
      --chapter-index <number>        Chapter index, default 0
      --maximum-page-count <number>   Pagination limit, default 100 (maximum 500)
      --json                          Emit a JSON summary
      --help                          Show this help
    """

    func parse(_ arguments: [String]) throws -> CLIArgumentResult {
        if arguments.contains("--help") { return .help }

        var sourcePath: String?
        var keyword: String?
        var searchPage = 1
        var bookIndex = 0
        var chapterIndex = 0
        var maximumPageCount = CLIOptions.defaultMaximumPageCount
        var usesJSONOutput = false
        var seen: Set<String> = []
        var index = 0

        while index < arguments.count {
            let argument = arguments[index]
            switch argument {
            case "--source":
                sourcePath = try value(after: &index, option: argument, arguments: arguments, seen: &seen)
            case "--keyword":
                keyword = try value(after: &index, option: argument, arguments: arguments, seen: &seen)
            case "--search-page":
                let value = try value(after: &index, option: argument, arguments: arguments, seen: &seen)
                searchPage = try integer(value, option: argument)
            case "--book-index":
                let value = try value(after: &index, option: argument, arguments: arguments, seen: &seen)
                bookIndex = try integer(value, option: argument)
            case "--chapter-index":
                let value = try value(after: &index, option: argument, arguments: arguments, seen: &seen)
                chapterIndex = try integer(value, option: argument)
            case "--maximum-page-count":
                let value = try value(after: &index, option: argument, arguments: arguments, seen: &seen)
                maximumPageCount = try integer(value, option: argument)
            case "--json":
                guard seen.insert(argument).inserted else { throw CLIArgumentError.duplicateOption(argument) }
                usesJSONOutput = true
            default:
                throw CLIArgumentError.unknownArgument(argument)
            }
            index += 1
        }

        guard let sourcePath, !sourcePath.isEmpty else {
            throw CLIArgumentError.missingRequiredOption("--source")
        }
        guard let keyword, !keyword.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw CLIArgumentError.missingRequiredOption("--keyword")
        }
        guard searchPage >= 1 else {
            throw CLIArgumentError.outOfRange(option: "--search-page", description: "must be at least 1")
        }
        guard bookIndex >= 0 else {
            throw CLIArgumentError.outOfRange(option: "--book-index", description: "must not be negative")
        }
        guard chapterIndex >= 0 else {
            throw CLIArgumentError.outOfRange(option: "--chapter-index", description: "must not be negative")
        }
        guard (1...CLIOptions.maximumAllowedPageCount).contains(maximumPageCount) else {
            throw CLIArgumentError.outOfRange(
                option: "--maximum-page-count",
                description: "must be between 1 and \(CLIOptions.maximumAllowedPageCount)"
            )
        }

        return .options(CLIOptions(
            sourcePath: sourcePath,
            keyword: keyword,
            searchPage: searchPage,
            bookIndex: bookIndex,
            chapterIndex: chapterIndex,
            maximumPageCount: maximumPageCount,
            usesJSONOutput: usesJSONOutput
        ))
    }

    private func value(
        after index: inout Int,
        option: String,
        arguments: [String],
        seen: inout Set<String>
    ) throws -> String {
        guard seen.insert(option).inserted else { throw CLIArgumentError.duplicateOption(option) }
        let valueIndex = index + 1
        guard arguments.indices.contains(valueIndex), !arguments[valueIndex].hasPrefix("--") else {
            throw CLIArgumentError.missingValue(option)
        }
        index = valueIndex
        return arguments[valueIndex]
    }

    private func integer(_ value: String, option: String) throws -> Int {
        guard let result = Int(value) else {
            throw CLIArgumentError.invalidInteger(option: option, value: value)
        }
        return result
    }
}
