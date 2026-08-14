import XCTest
@testable import LegadoIOS

@MainActor
final class TOCViewModelTests: XCTestCase {
    func testLoadingTransitionsToSuccess() async {
        let expected = [testChapter()]
        let viewModel = TOCViewModel(
            source: testSource(),
            book: testBookInfo(),
            service: FakeTOCService(result: .success(expected), delay: .milliseconds(20))
        )

        let task = Task { await viewModel.loadIfNeeded() }
        await Task.yield()
        XCTAssertTrue(viewModel.isLoading)
        await task.value

        XCTAssertEqual(viewModel.chapters, expected)
        XCTAssertTrue(viewModel.hasLoaded)
        XCTAssertNil(viewModel.errorMessage)
    }

    func testEmptyResultIsACompletedLoad() async {
        let viewModel = TOCViewModel(
            source: testSource(),
            book: testBookInfo(),
            service: FakeTOCService(result: .success([]))
        )

        await viewModel.loadIfNeeded()

        XCTAssertTrue(viewModel.hasLoaded)
        XCTAssertTrue(viewModel.chapters.isEmpty)
        XCTAssertNil(viewModel.errorMessage)
    }

    func testFailureCanBeRetried() async {
        let viewModel = TOCViewModel(
            source: testSource(),
            book: testBookInfo(),
            service: FakeTOCService(result: .failure(.expected))
        )

        await viewModel.loadIfNeeded()

        XCTAssertFalse(viewModel.hasLoaded)
        XCTAssertNotNil(viewModel.errorMessage)
    }
}
