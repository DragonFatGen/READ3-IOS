import LegadoCore
import XCTest
@testable import LegadoIOS

@MainActor
final class ReaderViewModelTests: XCTestCase {
    func testInitialChapterLoadAndNavigationBoundaries() async {
        let service = RecordingContentService()
        let store = MemoryProgressStore()
        let model = makeModel(service: service, store: store)

        XCTAssertFalse(model.previousChapterAvailable)
        XCTAssertTrue(model.nextChapterAvailable)
        model.loadInitialChapter()
        await waitUntil { model.content != nil }
        XCTAssertEqual(model.content?.content, "正文 0")

        model.goToPreviousChapter()
        XCTAssertEqual(model.currentChapterIndex, 0)
        model.goToNextChapter()
        await waitUntil { model.content?.content == "正文 1" }
        XCTAssertEqual(model.currentChapterIndex, 1)
        model.goToNextChapter()
        await waitUntil { model.content?.content == "正文 2" }
        XCTAssertFalse(model.nextChapterAvailable)
    }

    func testErrorAndRetry() async {
        let service = RecordingContentService(failuresBeforeSuccess: 1)
        let model = makeModel(service: service, store: MemoryProgressStore())
        model.loadInitialChapter()
        await waitUntil { model.errorMessage != nil }
        XCTAssertNil(model.content)

        model.retry()
        await waitUntil { model.content != nil }
        XCTAssertNil(model.errorMessage)
    }

    func testStaleRequestCannotOverwriteSelectedChapter() async {
        let service = RecordingContentService(delays: [0: .milliseconds(80), 2: .milliseconds(5)])
        let model = makeModel(service: service, store: MemoryProgressStore())
        model.loadInitialChapter()
        model.goToChapter(at: 2)
        await waitUntil { model.content?.content == "正文 2" }
        try? await Task.sleep(for: .milliseconds(100))
        XCTAssertEqual(model.currentChapterIndex, 2)
        XCTAssertEqual(model.content?.content, "正文 2")
    }

    func testProgressRestoreAndSave() async {
        let store = MemoryProgressStore()
        store.value = ReadingProgress(
            lastChapterURL: testChapter(index: 1).url,
            lastChapterName: testChapter(index: 1).name,
            lastChapterIndex: 1,
            chapterProgress: 0.42,
            chapterCount: 3,
            lastReadAt: Date()
        )
        let model = makeModel(initialIndex: 1, service: RecordingContentService(), store: store)
        XCTAssertEqual(model.consumeRestorationProgress(), 0.42)
        model.updateProgress(0.7)
        model.saveProgressNow()
        XCTAssertEqual(store.value?.chapterProgress, 0.7)
    }

    func testChapterSwitchSavesOldChapterProgress() async {
        let store = MemoryProgressStore()
        let model = makeModel(service: RecordingContentService(), store: store)
        model.updateProgress(0.6)
        model.goToNextChapter()
        XCTAssertEqual(store.history.first?.lastChapterIndex, 0)
        XCTAssertEqual(store.history.first?.chapterProgress, 0.6)
    }

    func testCancellationIsNotAnError() async {
        let service = RecordingContentService(delays: [0: .seconds(1)])
        let model = makeModel(service: service, store: MemoryProgressStore())
        model.loadInitialChapter()
        model.cancel()
        await Task.yield()
        XCTAssertNil(model.errorMessage)
    }

    func testSuccessfulLoadPreloadsNextThenPreviousChapter() async {
        let service = RecordingContentService()
        let model = makeModel(initialIndex: 1, service: service, store: MemoryProgressStore())
        model.loadInitialChapter()
        await waitUntil { model.content != nil }
        for _ in 0..<200 {
            if await service.requestedIndices.count >= 3 { break }
            try? await Task.sleep(for: .milliseconds(2))
        }
        let requested = await service.requestedIndices
        XCTAssertEqual(Array(requested.prefix(3)), [1, 2, 0])
    }

    func testReloadUsesIgnoringCachePolicy() async {
        let service = RecordingContentService()
        let model = makeModel(service: service, store: MemoryProgressStore())
        model.reloadCurrentChapter()
        await waitUntil { model.content != nil }
        let policies = await service.requestedPolicies
        XCTAssertEqual(policies.first, .reloadIgnoringCache)
    }

    func testPagedLoadTriggersPaginationWhileScrollDoesNot() async {
        let pagedPaginator = FakeReaderPaginator(pageCount: 3)
        let paged = makeModel(
            service: RecordingContentService(), store: MemoryProgressStore(),
            paginator: pagedPaginator, layoutMode: .paged
        )
        paged.updatePaginationConfiguration(testConfiguration())
        paged.loadInitialChapter()
        await waitUntil { paged.pages.count == 3 }
        let pagedCalls = await pagedPaginator.callCount
        XCTAssertEqual(pagedCalls, 1)

        let scrollPaginator = FakeReaderPaginator(pageCount: 3)
        let scroll = makeModel(
            service: RecordingContentService(), store: MemoryProgressStore(),
            paginator: scrollPaginator, layoutMode: .scroll
        )
        scroll.updatePaginationConfiguration(testConfiguration())
        scroll.loadInitialChapter()
        await waitUntil { scroll.content != nil }
        let scrollCalls = await scrollPaginator.callCount
        XCTAssertEqual(scrollCalls, 0)
    }

    func testPageNavigationAndNormalizedProgress() async {
        let model = makePagedModel(pageCount: 3)
        await waitUntil { model.pages.count == 3 }
        XCTAssertEqual(model.currentPageIndex, 0)
        model.turnPageForward()
        XCTAssertEqual(model.currentPageIndex, 1)
        XCTAssertEqual(model.chapterProgress, 0.5)
        model.turnPageBackward()
        XCTAssertEqual(model.currentPageIndex, 0)
        XCTAssertEqual(model.chapterProgress, 0)
    }

    func testPageBoundariesCrossChaptersAtCorrectEnds() async {
        let forward = makePagedModel(initialIndex: 1, pageCount: 3)
        await waitUntil { forward.pages.count == 3 }
        forward.selectPage(2)
        forward.turnPageForward()
        await waitUntil { forward.currentChapterIndex == 2 && forward.pages.count == 3 }
        XCTAssertEqual(forward.currentPageIndex, 0)

        let backward = makePagedModel(initialIndex: 1, pageCount: 3)
        await waitUntil { backward.pages.count == 3 }
        backward.turnPageBackward()
        await waitUntil { backward.currentChapterIndex == 0 && backward.pages.count == 3 }
        XCTAssertEqual(backward.currentPageIndex, 2)
    }

    func testSavedProgressRestoresToEquivalentPage() async {
        let store = MemoryProgressStore()
        store.value = ReadingProgress(
            lastChapterURL: testChapter(index: 1).url,
            lastChapterName: testChapter(index: 1).name,
            lastChapterIndex: 1,
            chapterProgress: 0.5,
            chapterCount: 3,
            lastReadAt: Date()
        )
        let model = makeModel(
            initialIndex: 1, service: RecordingContentService(), store: store,
            paginator: FakeReaderPaginator(pageCount: 5), layoutMode: .paged
        )
        model.updatePaginationConfiguration(testConfiguration())
        model.loadInitialChapter()
        await waitUntil { model.pages.count == 5 }
        XCTAssertEqual(model.currentPageIndex, 2)
    }

    func testLayoutChangesRepaginateAndPreserveProgress() async {
        let paginator = FakeReaderPaginator(pageCount: 5)
        let model = makeModel(
            service: RecordingContentService(), store: MemoryProgressStore(),
            paginator: paginator, layoutMode: .paged
        )
        model.updatePaginationConfiguration(testConfiguration())
        model.loadInitialChapter()
        await waitUntil { model.pages.count == 5 }
        model.selectPage(2)

        for configuration in [
            testConfiguration(fontSize: 22),
            testConfiguration(fontSize: 22, lineSpacing: 12),
            testConfiguration(fontSize: 22, lineSpacing: 12, padding: 30),
            testConfiguration(
                size: CGSize(width: 480, height: 320),
                fontSize: 22,
                lineSpacing: 12,
                padding: 30
            )
        ] {
            model.updatePaginationConfiguration(configuration)
            await waitUntil { !model.isPaginating }
            XCTAssertEqual(model.currentPageIndex, 2)
        }
        let calls = await paginator.callCount
        XCTAssertEqual(calls, 5)
    }

    func testThemeAndPageTurnStyleDoNotCauseRepagination() async {
        let paginator = FakeReaderPaginator(pageCount: 3)
        let model = makeModel(
            service: RecordingContentService(), store: MemoryProgressStore(),
            paginator: paginator, layoutMode: .paged
        )
        model.updatePaginationConfiguration(testConfiguration())
        model.loadInitialChapter()
        await waitUntil { model.pages.count == 3 }
        let before = await paginator.callCount
        let defaults = UserDefaults(suiteName: "ReaderThemeTest.\(UUID().uuidString)")!
        let settings = ReaderSettingsStore(defaults: defaults, keyPrefix: "settings")
        settings.selectTheme(.dark)
        settings.selectPageTurnStyle(.none)
        let after = await paginator.callCount
        XCTAssertEqual(before, after)
    }

    func testStalePaginationCannotOverwriteNewConfiguration() async {
        let paginator = FakeReaderPaginator(pageCount: 2, delay: .milliseconds(40))
        let model = makeModel(
            service: RecordingContentService(), store: MemoryProgressStore(),
            paginator: paginator, layoutMode: .paged
        )
        model.updatePaginationConfiguration(testConfiguration(fontSize: 18))
        model.loadInitialChapter()
        await waitUntil { model.content != nil }
        model.updatePaginationConfiguration(testConfiguration(fontSize: 26))
        await waitUntil { model.pages.first?.text.hasPrefix("26.0") == true }
        XCTAssertTrue(model.pages.allSatisfy { $0.text.hasPrefix("26.0") })
    }

    func testEmptyAndOnePagePaginationAreSafe() async {
        let empty = makePagedModel(pageCount: 0)
        await waitUntil { !empty.isPaginating && empty.content != nil }
        XCTAssertEqual(empty.pages.count, 1)
        XCTAssertEqual(empty.currentPageIndex, 0)

        let one = makePagedModel(pageCount: 1)
        await waitUntil { one.pages.count == 1 }
        one.turnPageForward()
        XCTAssertEqual(one.chapterProgress, 0)
    }

    func testSwitchingModesPreservesApproximateProgress() async {
        let paginator = FakeReaderPaginator(pageCount: 5)
        let model = makeModel(
            service: RecordingContentService(), store: MemoryProgressStore(),
            paginator: paginator, layoutMode: .scroll
        )
        model.updatePaginationConfiguration(testConfiguration())
        model.loadInitialChapter()
        await waitUntil { model.content != nil }
        model.updateProgress(0.5)
        model.setLayoutMode(.paged)
        await waitUntil { model.pages.count == 5 }
        XCTAssertEqual(model.currentPageIndex, 2)
        model.setLayoutMode(.scroll)
        XCTAssertEqual(model.consumeRestorationProgress(), 0.5)
    }

    func testPagedReaderUsesCachedContentService() async {
        let source = testSource()
        let book = testBookInfo()
        let chapter = testChapter()
        let key = ChapterCacheKey(source: source, book: book, chapter: chapter)
        let cache = ReaderTestCache(entry: ChapterContentCacheEntry(
            key: key,
            chapterName: chapter.name,
            content: "cached body",
            chapterURL: chapter.url,
            cachedAt: Date()
        ))
        let upstream = ReaderCountingContentService()
        let service = CachedContentService(cache: cache, upstream: upstream)
        let model = ReaderViewModel(
            source: source,
            book: book,
            libraryBookID: "book",
            chapters: [chapter],
            initialChapterIndex: 0,
            contentService: service,
            progressStore: MemoryProgressStore(),
            paginator: FakeReaderPaginator(pageCount: 2),
            layoutMode: .paged
        )
        model.updatePaginationConfiguration(testConfiguration())
        model.loadInitialChapter()
        await waitUntil { model.pages.count == 2 }
        XCTAssertEqual(model.content?.content, "cached body")
        let requests = await upstream.requestedIndices
        XCTAssertTrue(requests.isEmpty)
    }

    func testBookmarkToggleAllowsDistinctPositionsAndRemovesNearbyMatch() async {
        let bookmarks = MemoryBookmarkStore()
        let model = makeModel(
            service: RecordingContentService(), store: MemoryProgressStore(),
            bookmarkStore: bookmarks
        )
        model.loadInitialChapter()
        await waitUntil { model.content != nil }
        model.updateProgress(0.2)
        model.toggleBookmark()
        model.updateProgress(0.7)
        model.toggleBookmark()
        XCTAssertEqual(model.bookmarks.count, 2)
        model.updateProgress(0.705)
        XCTAssertTrue(model.isCurrentPositionBookmarked)
        model.toggleBookmark()
        XCTAssertEqual(model.bookmarks.count, 1)
    }

    func testPagedBookmarkJumpAndSliderMapNormalizedProgress() async {
        let bookmarks = MemoryBookmarkStore()
        let model = makeModel(
            service: RecordingContentService(), store: MemoryProgressStore(),
            bookmarkStore: bookmarks,
            paginator: FakeReaderPaginator(pageCount: 5), layoutMode: .paged
        )
        model.updatePaginationConfiguration(testConfiguration())
        model.loadInitialChapter()
        await waitUntil { model.pages.count == 5 }
        model.seek(to: 0.75)
        XCTAssertEqual(model.currentPageIndex, 3)
        XCTAssertEqual(model.currentNormalizedProgress, 0.75)

        let bookmark = testBookmark(chapter: 2, progress: 0.5)
        bookmarks.add(bookmark)
        model.goToBookmark(bookmark)
        await waitUntil { model.currentChapterIndex == 2 && model.pages.count == 5 }
        XCTAssertEqual(model.currentPageIndex, 2)
    }

    func testScrollBookmarkJumpRestoresProgressAndClampsSlider() async {
        let bookmarks = MemoryBookmarkStore()
        let model = makeModel(
            service: RecordingContentService(), store: MemoryProgressStore(),
            bookmarkStore: bookmarks
        )
        model.loadInitialChapter()
        await waitUntil { model.content != nil }
        model.seek(to: 2)
        XCTAssertEqual(model.currentNormalizedProgress, 1)
        XCTAssertEqual(model.consumeRestorationProgress(), 1)

        let bookmark = testBookmark(chapter: 1, progress: 0.35)
        bookmarks.add(bookmark)
        model.goToBookmark(bookmark)
        await waitUntil { model.currentChapterIndex == 1 && model.content != nil }
        XCTAssertEqual(model.currentNormalizedProgress, 0.35)
        XCTAssertEqual(model.consumeRestorationProgress(), 0.35)
    }

    private func makeModel(
        initialIndex: Int = 0,
        service: any ChapterContentLoading,
        store: MemoryProgressStore,
        bookmarkStore: (any BookmarkStoring)? = nil,
        paginator: any ReaderPaginating = FakeReaderPaginator(pageCount: 3),
        layoutMode: ReaderLayoutMode = .scroll
    ) -> ReaderViewModel {
        ReaderViewModel(
            source: testSource(), book: testBookInfo(), libraryBookID: "book",
            chapters: (0..<3).map(testChapter), initialChapterIndex: initialIndex,
            contentService: service, progressStore: store,
            bookmarkStore: bookmarkStore,
            paginator: paginator, layoutMode: layoutMode
        )
    }

    private func testBookmark(chapter: Int, progress: Double) -> ReaderBookmark {
        ReaderBookmark(
            id: UUID(), bookID: "book", sourceIdentity: testSource().bookSourceUrl,
            bookIdentity: testBookInfo().bookURL, chapterIndex: chapter,
            chapterURL: testChapter(index: chapter).url,
            chapterName: testChapter(index: chapter).name,
            chapterProgress: progress, previewText: "preview", createdAt: Date()
        )
    }

    private func makePagedModel(initialIndex: Int = 0, pageCount: Int) -> ReaderViewModel {
        let model = makeModel(
            initialIndex: initialIndex,
            service: RecordingContentService(),
            store: MemoryProgressStore(),
            paginator: FakeReaderPaginator(pageCount: pageCount),
            layoutMode: .paged
        )
        model.updatePaginationConfiguration(testConfiguration())
        model.loadInitialChapter()
        return model
    }

    private func testConfiguration(
        size: CGSize = CGSize(width: 320, height: 480),
        fontSize: CGFloat = 19,
        lineSpacing: CGFloat = 8,
        padding: CGFloat = 20
    ) -> PaginationConfiguration {
        PaginationConfiguration(
            size: size,
            fontSize: fontSize,
            lineSpacing: lineSpacing,
            horizontalPadding: padding,
            verticalPadding: 20
        )
    }

    private func waitUntil(
        attempts: Int = 200,
        condition: @MainActor () -> Bool
    ) async {
        for _ in 0..<attempts {
            if condition() { return }
            try? await Task.sleep(for: .milliseconds(2))
        }
        XCTFail("Timed out waiting for ReaderViewModel state")
    }
}

private actor FakeReaderPaginator: ReaderPaginating {
    private let pageCount: Int
    private let delay: Duration
    private(set) var callCount = 0

    init(pageCount: Int, delay: Duration = .zero) {
        self.pageCount = pageCount
        self.delay = delay
    }

    func paginate(text: String, configuration: PaginationConfiguration) async -> [ReaderPage] {
        callCount += 1
        if delay > .zero { try? await Task.sleep(for: delay) }
        guard pageCount > 0 else { return [] }
        return (0..<pageCount).map { index in
            ReaderPage(
                index: index,
                utf16Range: index..<(index + 1),
                text: "\(configuration.fontSize)-page-\(index)"
            )
        }
    }
}

@MainActor
private final class MemoryProgressStore: ReadingProgressStoring {
    var value: ReadingProgress?
    var history: [ReadingProgress] = []
    func progress(for bookID: String) -> ReadingProgress? { value }
    func saveProgress(_ progress: ReadingProgress, for bookID: String) {
        value = progress
        history.append(progress)
    }
}

@MainActor
private final class MemoryBookmarkStore: BookmarkStoring {
    private var values: [ReaderBookmark] = []
    func bookmarks(for bookID: String) -> [ReaderBookmark] {
        values.filter { $0.bookID == bookID }.sorted {
            ($0.chapterIndex, $0.chapterProgress) < ($1.chapterIndex, $1.chapterProgress)
        }
    }
    func add(_ bookmark: ReaderBookmark) { values.append(bookmark) }
    func remove(id: UUID) { values.removeAll { $0.id == id } }
    func removeAll(for bookID: String) { values.removeAll { $0.bookID == bookID } }
}

private actor RecordingContentService: ChapterContentLoading {
    private var remainingFailures: Int
    private let delays: [Int: Duration]
    private(set) var requestedIndices: [Int] = []
    private(set) var requestedPolicies: [ContentLoadPolicy] = []

    init(failuresBeforeSuccess: Int = 0, delays: [Int: Duration] = [:]) {
        remainingFailures = failuresBeforeSuccess
        self.delays = delays
    }

    func loadContent(
        source: BookSource,
        book: BookInfoResult,
        chapter: BookChapterResult,
        policy: ContentLoadPolicy
    ) async throws -> ChapterContentResult {
        requestedIndices.append(chapter.index)
        requestedPolicies.append(policy)
        if let delay = delays[chapter.index] { try await Task.sleep(for: delay) }
        if remainingFailures > 0 {
            remainingFailures -= 1
            throw ViewModelTestError.expected
        }
        return ChapterContentResult(content: "正文 \(chapter.index)", chapterURL: chapter.url)
    }
}

private actor ReaderCountingContentService: ChapterContentLoading {
    private(set) var requestedIndices: [Int] = []

    func loadContent(
        source: BookSource,
        book: BookInfoResult,
        chapter: BookChapterResult,
        policy: ContentLoadPolicy
    ) async throws -> ChapterContentResult {
        _ = policy
        requestedIndices.append(chapter.index)
        return ChapterContentResult(content: "network", chapterURL: chapter.url)
    }
}

private actor ReaderTestCache: ChapterContentCache {
    private var entry: ChapterContentCacheEntry?

    init(entry: ChapterContentCacheEntry?) { self.entry = entry }

    func content(for key: ChapterCacheKey) async -> ChapterContentCacheEntry? {
        entry?.key == key ? entry : nil
    }
    func save(_ entry: ChapterContentCacheEntry) async throws { self.entry = entry }
    func remove(_ key: ChapterCacheKey) async { if entry?.key == key { entry = nil } }
    func removeAll(for book: ChapterCacheBookKey) async {
        if entry?.key.bookKey == book { entry = nil }
    }
    func clearExpired(before date: Date) async {
        if let cachedAt = entry?.cachedAt, cachedAt < date { entry = nil }
    }
    func clearAll() async { entry = nil }
}
