import LegadoCore
import XCTest
@testable import LegadoIOS

@MainActor
final class SearchViewModelTests: XCTestCase {
    func testChangingSourceImmediatelyEndsCancelledLoadingAndRejectsLateResult() async {
        let service = SuspendedSearchService()
        let model = SearchViewModel(source: testSource(), service: service)
        model.query = "old"
        model.search()
        for _ in 0..<200 {
            if await service.isPending { break }
            await Task.yield()
        }
        let pending = await service.isPending
        XCTAssertTrue(pending)
        let selected = BookSource(bookSourceUrl: "https://new.invalid", bookSourceName: "新书源")
        model.selectSource(selected)
        XCTAssertFalse(model.isLoading)
        XCTAssertFalse(model.hasSearched)
        XCTAssertTrue(model.results.isEmpty)
        await service.complete()
        // The injected service intentionally ignores cancellation until released.
        for _ in 0..<20 { await Task.yield() }
        XCTAssertEqual(model.source, selected)
        XCTAssertTrue(model.results.isEmpty)
        XCTAssertNil(model.errorMessage)
    }

    func testSearchFailureRetriesThenDisplaysEmptyResult() async {
        let model = SearchViewModel(source: testSource(), service: RetryingSearchService())
        model.query = "test"
        model.search()
        await wait { !model.isLoading }
        XCTAssertNotNil(model.errorMessage)
        model.search()
        await wait { !model.isLoading }
        XCTAssertNil(model.errorMessage)
        XCTAssertTrue(model.hasSearched)
        XCTAssertTrue(model.results.isEmpty)
    }

    func testDisabledSelectionFallsBackAndNilPreventsRequest() async {
        let service = RecordingSearchService()
        let first = BookSource(bookSourceUrl: "https://first.example", bookSourceName: "一")
        let second = BookSource(bookSourceUrl: "https://second.example", bookSourceName: "二")
        let viewModel = SearchViewModel(source: first, service: service)
        viewModel.query = "测试"

        viewModel.selectSource(second)
        viewModel.search()
        await wait { !viewModel.isLoading && viewModel.hasSearched }
        var identities = await service.identities
        XCTAssertEqual(identities, [second.bookSourceUrl])

        viewModel.selectSource(nil)
        viewModel.search()
        try? await Task.sleep(for: .milliseconds(10))
        identities = await service.identities
        XCTAssertEqual(identities, [second.bookSourceUrl])
    }

    private func wait(until condition: @escaping () -> Bool) async {
        for _ in 0..<100 {
            if condition() { return }
            try? await Task.sleep(for: .milliseconds(2))
        }
        XCTFail("Timed out waiting for search")
    }
}

private actor SuspendedSearchService: BookSearching {
    private var continuation: CheckedContinuation<[BookSearchResult], Never>?
    var isPending: Bool { continuation != nil }

    func search(source: BookSource, keyword: String) async throws -> [BookSearchResult] {
        await withCheckedContinuation { continuation = $0 }
    }

    func complete() {
        continuation?.resume(returning: [testSearchResult()])
        continuation = nil
    }
}

private actor RetryingSearchService: BookSearching {
    private var failed = false
    func search(source: BookSource, keyword: String) async throws -> [BookSearchResult] {
        if !failed {
            failed = true
            throw ViewModelTestError.expected
        }
        return []
    }
}

private actor RecordingSearchService: BookSearching {
    private(set) var identities: [String] = []
    func search(source: BookSource, keyword: String) async throws -> [BookSearchResult] {
        identities.append(source.bookSourceUrl)
        return []
    }
}
