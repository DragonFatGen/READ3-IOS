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

    private func makeModel(
        initialIndex: Int = 0,
        service: RecordingContentService,
        store: MemoryProgressStore
    ) -> ReaderViewModel {
        ReaderViewModel(
            source: testSource(), book: testBookInfo(), libraryBookID: "book",
            chapters: (0..<3).map(testChapter), initialChapterIndex: initialIndex,
            contentService: service, progressStore: store
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

private actor RecordingContentService: ChapterContentLoading {
    private var remainingFailures: Int
    private let delays: [Int: Duration]

    init(failuresBeforeSuccess: Int = 0, delays: [Int: Duration] = [:]) {
        remainingFailures = failuresBeforeSuccess
        self.delays = delays
    }

    func loadContent(
        source: BookSource,
        book: BookInfoResult,
        chapter: BookChapterResult
    ) async throws -> ChapterContentResult {
        if let delay = delays[chapter.index] { try await Task.sleep(for: delay) }
        if remainingFailures > 0 {
            remainingFailures -= 1
            throw ViewModelTestError.expected
        }
        return ChapterContentResult(content: "正文 \(chapter.index)", chapterURL: chapter.url)
    }
}
