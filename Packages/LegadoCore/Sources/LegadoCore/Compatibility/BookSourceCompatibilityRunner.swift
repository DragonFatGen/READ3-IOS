import Foundation

public enum CompatibilityStage: String, Codable, Sendable, Equatable, CaseIterable {
    case `import`
    case search
    case bookInfo
    case toc
    case content
    case request
    case charset
    case ruleParser
    case selector
    case javascript
    case unsupportedCapability
}

public struct CompatibilityFailure: Codable, Sendable, Equatable {
    /// The most specific failure category available.
    public let stage: CompatibilityStage
    /// The business operation active when a cross-cutting failure occurred.
    public let operation: CompatibilityStage?
    public let message: String

    public init(stage: CompatibilityStage, operation: CompatibilityStage?, message: String) {
        self.stage = stage
        self.operation = operation
        self.message = message
    }
}

public struct CompatibilityReport: Sendable, Equatable {
    public let source: BookSource?
    public let importWarnings: [SourceImportWarning]
    public let migrations: [SourceMigration]
    public let searchResults: [BookSearchResult]
    public let selectedSearchResult: BookSearchResult?
    public let bookInfo: BookInfoResult?
    public let chapters: [BookChapterResult]
    public let selectedChapter: BookChapterResult?
    public let content: ChapterContentResult?
    public let failure: CompatibilityFailure?

    public var isSuccessful: Bool { failure == nil && content != nil }

    public init(
        source: BookSource? = nil,
        importWarnings: [SourceImportWarning] = [],
        migrations: [SourceMigration] = [],
        searchResults: [BookSearchResult] = [],
        selectedSearchResult: BookSearchResult? = nil,
        bookInfo: BookInfoResult? = nil,
        chapters: [BookChapterResult] = [],
        selectedChapter: BookChapterResult? = nil,
        content: ChapterContentResult? = nil,
        failure: CompatibilityFailure? = nil
    ) {
        self.source = source
        self.importWarnings = importWarnings
        self.migrations = migrations
        self.searchResults = searchResults
        self.selectedSearchResult = selectedSearchResult
        self.bookInfo = bookInfo
        self.chapters = chapters
        self.selectedChapter = selectedChapter
        self.content = content
        self.failure = failure
    }
}

/// Runs the production Core stages with injected dependencies and captures a
/// deterministic report. Fixture matching remains a test-transport concern.
public struct BookSourceCompatibilityRunner: Sendable {
    private let importer: BookSourceImporter
    private let searchRuntime: BookSourceSearchRuntime
    private let bookInfoRuntime: BookSourceBookInfoRuntime
    private let tocRuntime: BookSourceTOCRuntime
    private let contentRuntime: BookSourceContentRuntime

    public init(
        httpClient: any HTTPClient,
        importer: BookSourceImporter = BookSourceImporter(),
        requestBuilder: RequestBuilder = RequestBuilder(),
        selectorExecutor: any RuleNodeSelectorExecutor = LegadoRuleSelectorExecutor(),
        javaScriptExecutor: (any RuleJavaScriptExecutor)? = nil,
        textDecoder: any TextDecoder = FoundationTextDecoder(),
        maximumPageCount: Int = 100
    ) {
        self.importer = importer
        searchRuntime = BookSourceSearchRuntime(
            httpClient: httpClient,
            requestBuilder: requestBuilder,
            selectorExecutor: selectorExecutor,
            javaScriptExecutor: javaScriptExecutor,
            textDecoder: textDecoder
        )
        bookInfoRuntime = BookSourceBookInfoRuntime(
            httpClient: httpClient,
            requestBuilder: requestBuilder,
            selectorExecutor: selectorExecutor,
            javaScriptExecutor: javaScriptExecutor,
            textDecoder: textDecoder
        )
        tocRuntime = BookSourceTOCRuntime(
            httpClient: httpClient,
            requestBuilder: requestBuilder,
            selectorExecutor: selectorExecutor,
            javaScriptExecutor: javaScriptExecutor,
            textDecoder: textDecoder,
            maximumPageCount: maximumPageCount
        )
        contentRuntime = BookSourceContentRuntime(
            httpClient: httpClient,
            requestBuilder: requestBuilder,
            selectorExecutor: selectorExecutor,
            javaScriptExecutor: javaScriptExecutor,
            textDecoder: textDecoder,
            maximumPageCount: maximumPageCount
        )
    }

    public func run(
        sourceJSON: Data,
        keyword: String,
        searchPage: Int = 1,
        bookIndex: Int = 0,
        chapterIndex: Int = 0
    ) async -> CompatibilityReport {
        let imported: SourceImportResult
        do {
            imported = try importer.importSource(from: sourceJSON)
        } catch {
            return CompatibilityReport(failure: failure(.import, error: error))
        }

        let source = imported.source
        let base = PartialReport(
            source: source,
            warnings: imported.warnings,
            migrations: imported.migrations
        )
        let searchResults: [BookSearchResult]
        do {
            searchResults = try await searchRuntime.search(
                source: source,
                keyword: keyword,
                page: searchPage
            )
        } catch {
            return base.report(failure: failure(.search, error: error))
        }
        guard searchResults.indices.contains(bookIndex) else {
            return base.with(searchResults: searchResults).report(
                failure: CompatibilityFailure(
                    stage: .search,
                    operation: .search,
                    message: "No search result exists at index \(bookIndex)."
                )
            )
        }
        let selectedBook = searchResults[bookIndex]
        let searched = base.with(searchResults: searchResults, selectedBook: selectedBook)

        let info: BookInfoResult
        do {
            info = try await bookInfoRuntime.fetchBookInfo(source: source, book: selectedBook)
        } catch {
            return searched.report(failure: failure(.bookInfo, error: error))
        }
        let informed = searched.with(bookInfo: info)

        let chapters: [BookChapterResult]
        do {
            chapters = try await tocRuntime.fetchTOC(source: source, book: info)
        } catch {
            return informed.report(failure: failure(.toc, error: error))
        }
        guard chapters.indices.contains(chapterIndex) else {
            return informed.with(chapters: chapters).report(
                failure: CompatibilityFailure(
                    stage: .toc,
                    operation: .toc,
                    message: "No chapter exists at index \(chapterIndex)."
                )
            )
        }
        let chapter = chapters[chapterIndex]
        let catalogued = informed.with(chapters: chapters, selectedChapter: chapter)

        do {
            let content = try await contentRuntime.fetchContent(
                source: source,
                book: info,
                chapter: chapter
            )
            return catalogued.with(content: content).report()
        } catch {
            return catalogued.report(failure: failure(.content, error: error))
        }
    }

    private func failure(_ operation: CompatibilityStage, error: any Error) -> CompatibilityFailure {
        let message = Self.redacted(error.localizedDescription)
        let category: CompatibilityStage
        switch error {
        case let value as BookSearchError:
            category = classify(value, message: message, fallback: operation)
        case let value as BookInfoError:
            category = classify(value, message: message, fallback: operation)
        case let value as TOCError:
            category = classify(value, message: message, fallback: operation)
        case let value as ContentError:
            category = classify(value, message: message, fallback: operation)
        case is SourceImportError:
            category = .import
        default:
            category = Self.messageCategory(message) ?? operation
        }
        return CompatibilityFailure(stage: category, operation: operation, message: message)
    }

    private func classify(
        _ error: BookSearchError,
        message: String,
        fallback: CompatibilityStage
    ) -> CompatibilityStage {
        switch error {
        case .requestBuildFailed, .networkFailed: .request
        case .responseDecodeFailed: .charset
        case .unsupportedStructuredRule, .unsupportedJavaScriptNetworkHost: .unsupportedCapability
        case .bookListRuleFailed, .fieldRuleFailed: Self.messageCategory(message) ?? .selector
        case .searchNotSupported: .unsupportedCapability
        case .requiredFieldMissing: fallback
        }
    }

    private func classify(
        _ error: BookInfoError,
        message: String,
        fallback: CompatibilityStage
    ) -> CompatibilityStage {
        switch error {
        case .requestBuildFailed, .networkFailed: .request
        case .responseDecodeFailed: .charset
        case .unsupportedStructuredRule, .unsupportedJavaScriptNetworkHost: .unsupportedCapability
        case .initRuleFailed, .fieldRuleFailed: Self.messageCategory(message) ?? .selector
        }
    }

    private func classify(
        _ error: TOCError,
        message: String,
        fallback: CompatibilityStage
    ) -> CompatibilityStage {
        switch error {
        case .requestBuildFailed, .networkFailed: .request
        case .responseDecodeFailed: .charset
        case .unsupportedStructuredRule, .unsupportedJavaScriptNetworkHost: .unsupportedCapability
        case .chapterListRuleFailed, .nextPageRuleFailed, .chapterFieldRuleFailed:
            Self.messageCategory(message) ?? .selector
        case .emptyChapterList, .paginationLimitExceeded: fallback
        }
    }

    private func classify(
        _ error: ContentError,
        message: String,
        fallback: CompatibilityStage
    ) -> CompatibilityStage {
        switch error {
        case .requestBuildFailed, .networkFailed: .request
        case .responseDecodeFailed: .charset
        case .unsupportedStructuredRule, .unsupportedJavaScriptNetworkHost: .unsupportedCapability
        case .contentRuleFailed, .nextPageRuleFailed, .purificationRuleFailed:
            Self.messageCategory(message) ?? .selector
        case .emptyContent, .paginationLimitExceeded: fallback
        }
    }

    private static func messageCategory(_ message: String) -> CompatibilityStage? {
        let value = message.lowercased()
        if value.contains("javascript") { return .javascript }
        if value.contains("unsupported") { return .unsupportedCapability }
        if value.contains("charset") || value.contains("decod") || value.contains("encod") {
            return .charset
        }
        if value.contains("syntax") || value.contains("unbalanced") ||
            value.contains("unterminated") || value.contains("prefix") ||
            value.contains("expression") || value.contains("regular expression") {
            return .ruleParser
        }
        if value.contains("selector") || value.contains("jsonpath") ||
            value.contains("xpath") || value.contains("document") {
            return .selector
        }
        return nil
    }

    private static func redacted(_ message: String) -> String {
        var value = message
        let replacements = [
            (
                #"(?i)(authorization|cookie|token|password|passwd|secret)(\s*[:=]\s*)[^\s,;}&]+"#,
                "$1$2<redacted>"
            ),
            (
                #"(?i)([?&](?:token|password|passwd|secret|key)=)[^&\s]+"#,
                "$1<redacted>"
            )
        ]
        for (pattern, replacement) in replacements {
            value = value.replacingOccurrences(
                of: pattern,
                with: replacement,
                options: .regularExpression
            )
        }
        return String(value.prefix(500))
    }
}

private struct PartialReport {
    var source: BookSource
    var warnings: [SourceImportWarning]
    var migrations: [SourceMigration]
    var searchResults: [BookSearchResult] = []
    var selectedBook: BookSearchResult?
    var bookInfo: BookInfoResult?
    var chapters: [BookChapterResult] = []
    var selectedChapter: BookChapterResult?
    var content: ChapterContentResult?

    func with(
        searchResults: [BookSearchResult]? = nil,
        selectedBook: BookSearchResult? = nil,
        bookInfo: BookInfoResult? = nil,
        chapters: [BookChapterResult]? = nil,
        selectedChapter: BookChapterResult? = nil,
        content: ChapterContentResult? = nil
    ) -> PartialReport {
        var copy = self
        if let searchResults { copy.searchResults = searchResults }
        if let selectedBook { copy.selectedBook = selectedBook }
        if let bookInfo { copy.bookInfo = bookInfo }
        if let chapters { copy.chapters = chapters }
        if let selectedChapter { copy.selectedChapter = selectedChapter }
        if let content { copy.content = content }
        return copy
    }

    func report(failure: CompatibilityFailure? = nil) -> CompatibilityReport {
        CompatibilityReport(
            source: source,
            importWarnings: warnings,
            migrations: migrations,
            searchResults: searchResults,
            selectedSearchResult: selectedBook,
            bookInfo: bookInfo,
            chapters: chapters,
            selectedChapter: selectedChapter,
            content: content,
            failure: failure
        )
    }
}
