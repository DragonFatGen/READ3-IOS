import LegadoCore
import XCTest
@testable import LegadoIOS

@MainActor
final class ExploreViewModelTests: XCTestCase {
    func testNoAvailableSourceClearsState() async {
        let service = FakeExploreService()
        let viewModel = ExploreViewModel(service: service)

        viewModel.updateAvailableSources([])

        XCTAssertNil(viewModel.source)
        XCTAssertTrue(viewModel.categories.isEmpty)
        XCTAssertTrue(viewModel.results.isEmpty)
    }

    func testLoadsCategoriesAndFirstSelectableCategory() async {
        let source = exploreSource("a")
        let service = FakeExploreService()
        await service.setCategories([.init(title: "分组"), .init(title: "热门", url: "/hot")], for: source)
        await service.setBooks([exploreBook("1")], source: source, url: "/hot", page: 1)
        let viewModel = ExploreViewModel(service: service)

        viewModel.updateAvailableSources([source])
        await wait { viewModel.currentPage == 1 }

        XCTAssertEqual(viewModel.categories.map(\.title), ["分组", "热门"])
        XCTAssertEqual(viewModel.selectedCategoryIndex, 1)
        XCTAssertEqual(viewModel.results.map(\.bookURL), ["https://books.example/1"])
    }

    func testHeaderWithoutURLCannotBeSelected() async {
        let source = exploreSource("a")
        let service = FakeExploreService()
        await service.setCategories([.init(title: "标题"), .init(title: "可选", url: "/list")], for: source)
        await service.setBooks([], source: source, url: "/list", page: 1)
        let viewModel = ExploreViewModel(service: service)
        viewModel.updateAvailableSources([source])
        await wait { viewModel.currentPage == 1 }

        viewModel.selectCategory(at: 0)

        XCTAssertEqual(viewModel.selectedCategoryIndex, 1)
        let calls = await service.exploreRequests
        XCTAssertEqual(calls.count, 1)
    }

    func testSelectingCategoryLoadsPageOneAndResetsResults() async {
        let source = exploreSource("a")
        let service = FakeExploreService()
        await service.setCategories([
            .init(title: "A", url: "/a"),
            .init(title: "B", url: "/b")
        ], for: source)
        await service.setBooks([exploreBook("a")], source: source, url: "/a", page: 1)
        await service.setBooks([exploreBook("b")], source: source, url: "/b", page: 1)
        let viewModel = ExploreViewModel(service: service)
        viewModel.updateAvailableSources([source])
        await wait { viewModel.results.first?.bookURL.hasSuffix("/a") == true }

        viewModel.selectCategory(at: 1)
        XCTAssertTrue(viewModel.results.isEmpty)
        XCTAssertEqual(viewModel.currentPage, 0)
        await wait { viewModel.results.first?.bookURL.hasSuffix("/b") == true }

        XCTAssertEqual(viewModel.currentPage, 1)
    }

    func testLoadMoreIncrementsPageAndAppendsInOrder() async {
        let (viewModel, service, source) = await preparedViewModel(firstPage: [exploreBook("1")])
        await service.setBooks([exploreBook("2"), exploreBook("3")], source: source, url: "/list", page: 2)

        viewModel.loadMore()
        await wait { viewModel.currentPage == 2 }

        XCTAssertEqual(viewModel.results.map(\.bookURL), [
            "https://books.example/1", "https://books.example/2", "https://books.example/3"
        ])
    }

    func testEmptyNextPageStopsPagination() async {
        let (viewModel, service, source) = await preparedViewModel(firstPage: [exploreBook("1")])
        await service.setBooks([], source: source, url: "/list", page: 2)

        viewModel.loadMore()
        await wait { viewModel.currentPage == 2 }

        XCTAssertFalse(viewModel.hasMore)
        XCTAssertEqual(viewModel.results.count, 1)
    }

    func testDuplicateBoundaryUsesBookURLAndDoesNotAppendPage() async {
        let existing = [exploreBook("1", name: "同名"), exploreBook("2", name: "同名")]
        let (viewModel, service, source) = await preparedViewModel(firstPage: existing)
        await service.setBooks(
            [exploreBook("1", name: "改名也是同一本"), exploreBook("2", name: "另一个名字")],
            source: source,
            url: "/list",
            page: 2
        )

        viewModel.loadMore()
        await wait { viewModel.currentPage == 2 }

        XCTAssertFalse(viewModel.hasMore)
        XCTAssertEqual(viewModel.results, existing)
    }

    func testPartialDuplicatePageIsAppendedWithoutPerItemDeduplication() async {
        let (viewModel, service, source) = await preparedViewModel(firstPage: [exploreBook("1")])
        await service.setBooks([exploreBook("1"), exploreBook("2")], source: source, url: "/list", page: 2)

        viewModel.loadMore()
        await wait { viewModel.currentPage == 2 }

        XCTAssertEqual(viewModel.results.map(\.bookURL), [
            "https://books.example/1", "https://books.example/1", "https://books.example/2"
        ])
        XCTAssertTrue(viewModel.hasMore)
    }

    func testSwitchingSourceResetsState() async {
        let first = exploreSource("first")
        let second = exploreSource("second")
        let service = FakeExploreService()
        await configureSingleCategory(service, source: first, book: exploreBook("first"))
        await configureSingleCategory(service, source: second, book: exploreBook("second"))
        let viewModel = ExploreViewModel(service: service)
        viewModel.updateAvailableSources([first, second])
        await wait { viewModel.results.first?.bookURL.hasSuffix("/first") == true }

        viewModel.selectSource(second)
        XCTAssertTrue(viewModel.results.isEmpty)
        XCTAssertEqual(viewModel.currentPage, 0)
        await wait { viewModel.results.first?.bookURL.hasSuffix("/second") == true }

        XCTAssertEqual(viewModel.source?.bookSourceUrl, second.bookSourceUrl)
    }

    func testCategoryCacheIsScopedBySourceForSession() async {
        let first = exploreSource("first")
        let second = exploreSource("second")
        let service = FakeExploreService()
        await configureSingleCategory(service, source: first, book: exploreBook("first"))
        await configureSingleCategory(service, source: second, book: exploreBook("second"))
        let viewModel = ExploreViewModel(service: service)
        viewModel.updateAvailableSources([first, second])
        await wait { viewModel.currentPage == 1 }
        viewModel.selectSource(second)
        await wait { viewModel.source == second && viewModel.currentPage == 1 }
        viewModel.selectSource(first)
        await wait { viewModel.source == first && viewModel.currentPage == 1 }

        let calls = await service.categoryRequests
        XCTAssertEqual(calls.filter { $0 == first.bookSourceUrl }.count, 1)
        XCTAssertEqual(calls.filter { $0 == second.bookSourceUrl }.count, 1)
    }

    func testRefreshCategoriesClearsOnlyCurrentSourceCache() async {
        let source = exploreSource("a")
        let service = FakeExploreService()
        await configureSingleCategory(service, source: source, book: exploreBook("1"))
        let viewModel = ExploreViewModel(service: service)
        viewModel.updateAvailableSources([source])
        await wait { viewModel.currentPage == 1 }

        viewModel.refreshCategories()
        await wait { (await service.categoryCallCount(for: source)) == 2 }

        let callCount = await service.categoryCallCount(for: source)
        XCTAssertEqual(callCount, 2)
    }

    func testRefreshingBooksDoesNotClearCategoryCache() async {
        let source = exploreSource("a")
        let service = FakeExploreService()
        await configureSingleCategory(service, source: source, book: exploreBook("1"))
        let viewModel = ExploreViewModel(service: service)
        viewModel.updateAvailableSources([source])
        await wait { viewModel.currentPage == 1 }

        await viewModel.refreshBooks()

        let callCount = await service.categoryCallCount(for: source)
        XCTAssertEqual(callCount, 1)
        XCTAssertEqual(viewModel.currentPage, 1)
    }

    func testFirstPageFailureShowsError() async {
        let source = exploreSource("a")
        let service = FakeExploreService()
        await service.setCategories([.init(title: "列表", url: "/list")], for: source)
        await service.setFailure(source: source, url: "/list", page: 1)
        let viewModel = ExploreViewModel(service: service)

        viewModel.updateAvailableSources([source])
        await wait { viewModel.errorMessage != nil }

        XCTAssertTrue(viewModel.results.isEmpty)
        XCTAssertFalse(viewModel.hasMore)
    }

    func testCategoryFailureShowsErrorWithoutStartingBookRequest() async {
        let source = exploreSource("a")
        let service = FakeExploreService()
        await service.setCategoryFailure(for: source)
        let viewModel = ExploreViewModel(service: service)

        viewModel.updateAvailableSources([source])
        await wait { viewModel.categoryErrorMessage != nil }

        XCTAssertTrue(viewModel.categories.isEmpty)
        XCTAssertNil(viewModel.selectedCategoryIndex)
        let requests = await service.exploreRequests
        XCTAssertTrue(requests.isEmpty)
    }

    func testLoadMoreFailurePreservesExistingResultsAndCanRetry() async {
        let (viewModel, service, source) = await preparedViewModel(firstPage: [exploreBook("1")])
        await service.setFailure(source: source, url: "/list", page: 2)
        viewModel.loadMore()
        await wait { viewModel.loadMoreErrorMessage != nil }

        XCTAssertEqual(viewModel.currentPage, 1)
        XCTAssertEqual(viewModel.results.count, 1)
        XCTAssertTrue(viewModel.hasMore)
    }

    func testStaleRequestCannotOverwriteNewCategory() async {
        let source = exploreSource("a")
        let service = FakeExploreService()
        await service.setCategories([
            .init(title: "慢", url: "/slow"),
            .init(title: "快", url: "/fast")
        ], for: source)
        await service.setBooks(
            [exploreBook("slow")], source: source, url: "/slow", page: 1,
            delay: .milliseconds(50), ignoreCancellation: true
        )
        await service.setBooks([exploreBook("fast")], source: source, url: "/fast", page: 1)
        let viewModel = ExploreViewModel(service: service)
        viewModel.updateAvailableSources([source])
        await wait { viewModel.isLoading }

        viewModel.selectCategory(at: 1)
        await wait { viewModel.results.first?.bookURL.hasSuffix("/fast") == true }
        try? await Task.sleep(for: .milliseconds(70))

        XCTAssertEqual(viewModel.results.map(\.bookURL), ["https://books.example/fast"])
    }

    func testStaleRequestCannotOverwriteNewSource() async {
        let first = exploreSource("first")
        let second = exploreSource("second")
        let service = FakeExploreService()
        await service.setCategories([.init(title: "列表", url: "/list")], for: first)
        await service.setCategories([.init(title: "列表", url: "/list")], for: second)
        await service.setBooks(
            [exploreBook("slow")], source: first, url: "/list", page: 1,
            delay: .milliseconds(50), ignoreCancellation: true
        )
        await service.setBooks([exploreBook("fast")], source: second, url: "/list", page: 1)
        let viewModel = ExploreViewModel(service: service)
        viewModel.updateAvailableSources([first, second])
        await wait { viewModel.source == first && viewModel.isLoading }

        viewModel.selectSource(second)
        await wait { viewModel.results.first?.bookURL.hasSuffix("/fast") == true }
        try? await Task.sleep(for: .milliseconds(70))

        XCTAssertEqual(viewModel.source, second)
        XCTAssertEqual(viewModel.results.map(\.bookURL), ["https://books.example/fast"])
    }

    func testConcurrentLoadMoreRequestsAreCoalesced() async {
        let (viewModel, service, source) = await preparedViewModel(firstPage: [exploreBook("1")])
        await service.setBooks(
            [exploreBook("2")], source: source, url: "/list", page: 2,
            delay: .milliseconds(30)
        )

        viewModel.loadMore()
        viewModel.loadMore()
        viewModel.loadMore()
        await wait { viewModel.currentPage == 2 }

        let calls = await service.exploreRequests
        XCTAssertEqual(calls.filter { $0.page == 2 }.count, 1)
    }

    func testRemovedOrDisabledSelectedSourceFallsBack() async {
        let first = exploreSource("first")
        let second = exploreSource("second")
        let service = FakeExploreService()
        await configureSingleCategory(service, source: first, book: exploreBook("first"))
        await configureSingleCategory(service, source: second, book: exploreBook("second"))
        let viewModel = ExploreViewModel(service: service)
        viewModel.updateAvailableSources([first, second])
        await wait { viewModel.source == first && viewModel.currentPage == 1 }

        viewModel.updateAvailableSources([second])
        await wait { viewModel.source == second && viewModel.currentPage == 1 }

        XCTAssertEqual(viewModel.results.map(\.bookURL), ["https://books.example/second"])
    }

    private func preparedViewModel(
        firstPage: [BookSearchResult]
    ) async -> (ExploreViewModel, FakeExploreService, BookSource) {
        let source = exploreSource("a")
        let service = FakeExploreService()
        await service.setCategories([.init(title: "列表", url: "/list")], for: source)
        await service.setBooks(firstPage, source: source, url: "/list", page: 1)
        let viewModel = ExploreViewModel(service: service)
        viewModel.updateAvailableSources([source])
        await wait { viewModel.currentPage == 1 }
        return (viewModel, service, source)
    }

    private func configureSingleCategory(
        _ service: FakeExploreService,
        source: BookSource,
        book: BookSearchResult
    ) async {
        await service.setCategories([.init(title: "列表", url: "/list")], for: source)
        await service.setBooks([book], source: source, url: "/list", page: 1)
    }

    private func wait(until condition: @escaping @MainActor () async -> Bool) async {
        for _ in 0..<200 {
            if await condition() { return }
            try? await Task.sleep(for: .milliseconds(2))
        }
        XCTFail("Timed out waiting for ExploreViewModel")
    }
}

private func exploreSource(_ identity: String) -> BookSource {
    BookSource(
        bookSourceUrl: "https://\(identity).source.example",
        bookSourceName: identity,
        exploreUrl: "列表::/list"
    )
}

private func exploreBook(_ identity: String, name: String? = nil) -> BookSearchResult {
    BookSearchResult(
        name: name ?? identity,
        author: "作者",
        bookURL: "https://books.example/\(identity)",
        sourceURL: "https://source.example",
        sourceName: "书源",
        sourceType: 0,
        sourceOrder: 0
    )
}

private actor FakeExploreService: BookExploring {
    struct ExploreRequest: Equatable, Sendable {
        let source: String
        let url: String
        let page: Int
    }

    private struct Response: Sendable {
        let result: Result<[BookSearchResult], FakeExploreError>
        let delay: Duration
        let ignoreCancellation: Bool
    }

    private var categoriesBySource: [String: [ExploreKind]] = [:]
    private var categoryFailures: Set<String> = []
    private var responses: [String: Response] = [:]
    private(set) var categoryRequests: [String] = []
    private(set) var exploreRequests: [ExploreRequest] = []

    func setCategories(_ categories: [ExploreKind], for source: BookSource) {
        categoriesBySource[source.bookSourceUrl] = categories
    }

    func setCategoryFailure(for source: BookSource) {
        categoryFailures.insert(source.bookSourceUrl)
    }

    func setBooks(
        _ books: [BookSearchResult],
        source: BookSource,
        url: String,
        page: Int,
        delay: Duration = .zero,
        ignoreCancellation: Bool = false
    ) {
        responses[key(source: source.bookSourceUrl, url: url, page: page)] = Response(
            result: .success(books),
            delay: delay,
            ignoreCancellation: ignoreCancellation
        )
    }

    func setFailure(source: BookSource, url: String, page: Int) {
        responses[key(source: source.bookSourceUrl, url: url, page: page)] = Response(
            result: .failure(.expected),
            delay: .zero,
            ignoreCancellation: false
        )
    }

    func categoryCallCount(for source: BookSource) -> Int {
        categoryRequests.filter { $0 == source.bookSourceUrl }.count
    }

    func categories(source: BookSource) async throws -> [ExploreKind] {
        categoryRequests.append(source.bookSourceUrl)
        if categoryFailures.contains(source.bookSourceUrl) {
            throw FakeExploreError.expected
        }
        return categoriesBySource[source.bookSourceUrl] ?? []
    }

    func explore(source: BookSource, url: String, page: Int) async throws -> [BookSearchResult] {
        exploreRequests.append(ExploreRequest(source: source.bookSourceUrl, url: url, page: page))
        let response = responses[key(source: source.bookSourceUrl, url: url, page: page)] ?? Response(
            result: .success([]), delay: .zero, ignoreCancellation: false
        )
        if response.delay > .zero {
            if response.ignoreCancellation {
                try? await Task.sleep(for: response.delay)
            } else {
                try await Task.sleep(for: response.delay)
            }
        }
        return try response.result.get()
    }

    private func key(source: String, url: String, page: Int) -> String {
        "\(source)|\(url)|\(page)"
    }
}

private enum FakeExploreError: Error, Sendable {
    case expected
}
