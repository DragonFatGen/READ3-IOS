import XCTest
import LegadoCore
@testable import LegadoIOS

@MainActor
final class ChapterContentViewModelTests: XCTestCase {
    func testLoadingTransitionsToSuccess() async {
        let expected = ChapterContentResult(content: "正文", chapterURL: testChapter().url)
        let viewModel = ChapterContentViewModel(
            source: testSource(),
            book: testBookInfo(),
            chapter: testChapter(),
            service: FakeContentService(result: .success(expected), delay: .milliseconds(20))
        )

        let task = Task { await viewModel.loadIfNeeded() }
        await Task.yield()
        XCTAssertTrue(viewModel.isLoading)
        await task.value

        XCTAssertEqual(viewModel.content, expected)
        XCTAssertFalse(viewModel.isLoading)
        XCTAssertNil(viewModel.errorMessage)
    }

    func testLoadingTransitionsToFailure() async {
        let viewModel = ChapterContentViewModel(
            source: testSource(),
            book: testBookInfo(),
            chapter: testChapter(),
            service: FakeContentService(result: .failure(.expected))
        )

        await viewModel.loadIfNeeded()

        XCTAssertNil(viewModel.content)
        XCTAssertFalse(viewModel.isLoading)
        XCTAssertNotNil(viewModel.errorMessage)
    }

    func testStaleRequestCannotOverwriteRetryResult() async {
        let service = SequencedContentService()
        let viewModel = ChapterContentViewModel(
            source: testSource(),
            book: testBookInfo(),
            chapter: testChapter(),
            service: service
        )

        let first = Task { await viewModel.loadIfNeeded() }
        while await service.numberOfRequests == 0 { await Task.yield() }
        let second = Task { await viewModel.retry() }
        await second.value
        await first.value

        XCTAssertEqual(viewModel.content?.content, "较新的正文")
    }
}

private actor SequencedContentService: ChapterContentLoading {
    private var requestCount = 0

    var numberOfRequests: Int { requestCount }

    func loadContent(
        source: BookSource,
        book: BookInfoResult,
        chapter: BookChapterResult
    ) async throws -> ChapterContentResult {
        requestCount += 1
        let current = requestCount
        try await Task.sleep(for: current == 1 ? .milliseconds(60) : .milliseconds(5))
        return ChapterContentResult(
            content: current == 1 ? "较旧的正文" : "较新的正文",
            chapterURL: chapter.url
        )
    }
}
