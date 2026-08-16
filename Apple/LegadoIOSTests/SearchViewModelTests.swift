import LegadoCore
import XCTest
@testable import LegadoIOS

@MainActor
final class SearchViewModelTests: XCTestCase {
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

private actor RecordingSearchService: BookSearching {
    private(set) var identities: [String] = []
    func search(source: BookSource, keyword: String) async throws -> [BookSearchResult] {
        identities.append(source.bookSourceUrl)
        return []
    }
}
