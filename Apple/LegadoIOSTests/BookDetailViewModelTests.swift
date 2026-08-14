import XCTest
@testable import LegadoIOS

@MainActor
final class BookDetailViewModelTests: XCTestCase {
    func testLoadingTransitionsToSuccess() async {
        let expected = testBookInfo()
        let viewModel = BookDetailViewModel(
            source: testSource(),
            searchResult: testSearchResult(),
            service: FakeBookInfoService(result: .success(expected), delay: .milliseconds(20))
        )

        let task = Task { await viewModel.loadIfNeeded() }
        await Task.yield()
        XCTAssertTrue(viewModel.isLoading)
        await task.value

        XCTAssertEqual(viewModel.bookInfo, expected)
        XCTAssertFalse(viewModel.isLoading)
        XCTAssertNil(viewModel.errorMessage)
    }

    func testLoadingTransitionsToFailure() async {
        let viewModel = BookDetailViewModel(
            source: testSource(),
            searchResult: testSearchResult(),
            service: FakeBookInfoService(result: .failure(.expected))
        )

        await viewModel.loadIfNeeded()

        XCTAssertNil(viewModel.bookInfo)
        XCTAssertFalse(viewModel.isLoading)
        XCTAssertNotNil(viewModel.errorMessage)
    }
}
