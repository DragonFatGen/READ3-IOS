import Foundation
import LegadoCore

struct CompatibilityReportDTO: Codable, Equatable {
    let successful: Bool
    let completedStage: String?
    let importWarningCount: Int
    let migrationCount: Int
    let searchResultCount: Int
    let selectedBookName: String?
    let selectedBookAuthor: String?
    let chapterCount: Int
    let selectedChapterName: String?
    let contentSucceeded: Bool
    let contentCharacterCount: Int?
    let failureCategory: String?
    let failureOperation: String?
    let requestFailureKind: String?
    let networkErrorDomain: String?
    let networkErrorCode: Int?
    let httpStatusCode: Int?
    let errorMessage: String?

    init(report: CompatibilityReport) {
        let selectedBookName = report.bookInfo?.name ?? report.selectedSearchResult?.name
        let selectedBookAuthor = report.bookInfo?.author ?? report.selectedSearchResult?.author
        successful = report.isSuccessful
        completedStage = Self.completedStage(report)
        importWarningCount = report.importWarnings.count
        migrationCount = report.migrations.count
        searchResultCount = report.searchResults.count
        self.selectedBookName = selectedBookName.map(BookSourceCompatibilityRunner.redacted)
        self.selectedBookAuthor = selectedBookAuthor.map(BookSourceCompatibilityRunner.redacted)
        chapterCount = report.chapters.count
        selectedChapterName = (report.selectedChapter?.name).map(BookSourceCompatibilityRunner.redacted)
        contentSucceeded = report.content != nil
        contentCharacterCount = report.content.map { $0.content.count }
        failureCategory = report.failure?.stage.rawValue
        failureOperation = report.failure?.operation?.rawValue
        requestFailureKind = report.failure?.requestDiagnostic?.kind.rawValue
        networkErrorDomain = report.failure?.requestDiagnostic?.errorDomain
        networkErrorCode = report.failure?.requestDiagnostic?.errorCode
        httpStatusCode = report.failure?.requestDiagnostic?.httpStatusCode
        errorMessage = (report.failure?.message).map(BookSourceCompatibilityRunner.redacted)
    }

    static func inputFailure(_ message: String) -> CompatibilityReportDTO {
        CompatibilityReportDTO(
            successful: false,
            completedStage: nil,
            importWarningCount: 0,
            migrationCount: 0,
            searchResultCount: 0,
            selectedBookName: nil,
            selectedBookAuthor: nil,
            chapterCount: 0,
            selectedChapterName: nil,
            contentSucceeded: false,
            contentCharacterCount: nil,
            failureCategory: "input",
            failureOperation: "import",
            errorMessage: message
        )
    }

    private init(
        successful: Bool,
        completedStage: String?,
        importWarningCount: Int,
        migrationCount: Int,
        searchResultCount: Int,
        selectedBookName: String?,
        selectedBookAuthor: String?,
        chapterCount: Int,
        selectedChapterName: String?,
        contentSucceeded: Bool,
        contentCharacterCount: Int?,
        failureCategory: String?,
        failureOperation: String?,
        errorMessage: String?
    ) {
        self.successful = successful
        self.completedStage = completedStage
        self.importWarningCount = importWarningCount
        self.migrationCount = migrationCount
        self.searchResultCount = searchResultCount
        self.selectedBookName = selectedBookName
        self.selectedBookAuthor = selectedBookAuthor
        self.chapterCount = chapterCount
        self.selectedChapterName = selectedChapterName
        self.contentSucceeded = contentSucceeded
        self.contentCharacterCount = contentCharacterCount
        self.failureCategory = failureCategory
        self.failureOperation = failureOperation
        self.errorMessage = errorMessage
        requestFailureKind = nil
        networkErrorDomain = nil
        networkErrorCode = nil
        httpStatusCode = nil
    }

    private static func completedStage(_ report: CompatibilityReport) -> String? {
        if report.content != nil { return CompatibilityStage.content.rawValue }
        if report.selectedChapter != nil { return CompatibilityStage.toc.rawValue }
        if report.bookInfo != nil { return CompatibilityStage.bookInfo.rawValue }
        if report.selectedSearchResult != nil { return CompatibilityStage.search.rawValue }
        if report.source != nil { return CompatibilityStage.import.rawValue }
        return nil
    }
}

struct CompatibilityReportRenderer {
    func humanReadable(_ report: CompatibilityReportDTO) -> String {
        [
            "Overall: \(report.successful ? "SUCCESS" : "FAILURE")",
            "Completed stage: \(report.completedStage ?? "none")",
            "Import warnings: \(report.importWarningCount)",
            "Migrations: \(report.migrationCount)",
            "Search results: \(report.searchResultCount)",
            "Selected book: \(display(report.selectedBookName))",
            "Selected author: \(display(report.selectedBookAuthor))",
            "Chapters: \(report.chapterCount)",
            "Selected chapter: \(display(report.selectedChapterName))",
            "Content succeeded: \(report.contentSucceeded ? "yes" : "no")",
            "Content characters: \(report.contentCharacterCount.map(String.init) ?? "n/a")",
            "Failure category: \(display(report.failureCategory))",
            "Failure operation: \(display(report.failureOperation))",
            "Request failure kind: \(display(report.requestFailureKind))",
            "Network error domain: \(display(report.networkErrorDomain))",
            "Network error code: \(report.networkErrorCode.map(String.init) ?? "n/a")",
            "HTTP status code: \(report.httpStatusCode.map(String.init) ?? "n/a")",
            "Error: \(display(report.errorMessage))"
        ].joined(separator: "\n")
    }

    func json(_ report: CompatibilityReportDTO) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return String(decoding: try encoder.encode(report), as: UTF8.self)
    }

    private func display(_ value: String?) -> String { value ?? "n/a" }
}
