import Foundation
import LegadoCore
import XCTest
@testable import LegadoIOS

@MainActor
final class LibraryViewModelTests: XCTestCase {
    func testSingleRefreshUsesDisabledSourceAndMissingSourceFailsSafely() async throws {
        let fixture = makeFixture(bookCount: 1)
        let book = try XCTUnwrap(fixture.repository.books.first)
        fixture.sourceStore.setEnabled(false, for: testSource().bookSourceUrl)
        await fixture.viewModel.refreshBook(book)
        XCTAssertEqual(fixture.repository.books.first?.lastKnownChapterCount, 1)
        XCTAssertFalse(fixture.viewModel.checkingBookIDs.contains(book.id))

        let missingFixture = makeFixture(bookCount: 1, importsSource: false)
        let missingBook = try XCTUnwrap(missingFixture.repository.books.first)
        await missingFixture.viewModel.refreshBook(missingBook)
        XCTAssertEqual(missingFixture.repository.books.first?.lastUpdateError, "书源不可用")
    }

    func testBatchChecksAllBooksContinuesAfterFailureAndBoundsConcurrency() async {
        let checker = RecordingUpdateChecker(failingBookNames: ["书 2"])
        let fixture = makeFixture(bookCount: 7, checker: checker)
        await fixture.viewModel.refreshAll()

        XCTAssertEqual(fixture.viewModel.lastSummary, LibraryRefreshSummary(succeeded: 6, failed: 1))
        XCTAssertEqual(fixture.repository.books.filter { $0.lastCheckedAt != nil }.count, 6)
        XCTAssertEqual(fixture.repository.books.filter { $0.lastUpdateError != nil }.count, 1)
        let maximumConcurrency = await checker.maximumConcurrency
        XCTAssertLessThanOrEqual(maximumConcurrency, 3)
    }

    func testBatchMissingSourcesFailIndependentlyWithoutCrashing() async {
        let fixture = makeFixture(bookCount: 2, importsSource: false)
        await fixture.viewModel.refreshAll()
        XCTAssertEqual(fixture.viewModel.lastSummary, LibraryRefreshSummary(succeeded: 0, failed: 2))
        XCTAssertTrue(fixture.repository.books.allSatisfy { $0.lastUpdateError == "书源不可用" })
    }

    func testCancellationPreservesCompletedResultsAndStopsRemainingBatches() async {
        let checker = RecordingUpdateChecker(fastBookName: "书 7")
        let fixture = makeFixture(bookCount: 8, checker: checker)
        let task = Task { await fixture.viewModel.refreshAll() }
        try? await Task.sleep(for: .milliseconds(25))
        task.cancel()
        await task.value

        let completed = fixture.repository.books.filter { $0.lastCheckedAt != nil }.count
        XCTAssertGreaterThanOrEqual(completed, 1)
        XCTAssertLessThan(completed, 8)
    }

    private func makeFixture(
        bookCount: Int,
        importsSource: Bool = true,
        checker: RecordingUpdateChecker = RecordingUpdateChecker()
    ) -> (repository: LibraryRepository, sourceStore: BookSourceStore, viewModel: LibraryViewModel) {
        let suite = "LibraryViewModelTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let repository = LibraryRepository(defaults: defaults, storageKey: "library")
        let sourceStore = BookSourceStore(defaults: defaults, storageKey: "sources")
        if importsSource { sourceStore.upsert(testSource()) }
        for index in 0..<bookCount {
            repository.add(source: testSource(), bookInfo: bookInfo(index: index))
        }
        return (
            repository, sourceStore,
            LibraryViewModel(repository: repository, sourceStore: sourceStore, checker: checker)
        )
    }

    private func bookInfo(index: Int) -> BookInfoResult {
        BookInfoResult(
            name: "书 \(index)", author: "作者", bookURL: "https://source.example/book/\(index)",
            tocURL: "https://source.example/book/\(index)/toc",
            sourceURL: testSource().bookSourceUrl, sourceName: testSource().bookSourceName,
            sourceType: 0, sourceOrder: 0
        )
    }
}

private enum UpdateTestError: Error, Sendable { case expected }

private actor RecordingUpdateChecker: BookUpdateChecking {
    private let failingBookNames: Set<String>
    private let fastBookName: String?
    private(set) var active = 0
    private(set) var maximumConcurrency = 0

    init(failingBookNames: Set<String> = [], fastBookName: String? = nil) {
        self.failingBookNames = failingBookNames
        self.fastBookName = fastBookName
    }

    func checkUpdate(for book: LibraryBook, source: BookSource) async throws -> BookUpdateResult {
        active += 1
        maximumConcurrency = max(maximumConcurrency, active)
        defer { active -= 1 }
        let delay: Duration = book.name == fastBookName ? .milliseconds(5) : .milliseconds(80)
        try await Task.sleep(for: delay)
        if failingBookNames.contains(book.name) { throw UpdateTestError.expected }
        return BookUpdateResult(
            checkedAt: Date(timeIntervalSince1970: 1), chapterCount: 1,
            latestChapterName: "第一章", latestChapterURL: "chapter-1", newChapterCount: 0
        )
    }
}
