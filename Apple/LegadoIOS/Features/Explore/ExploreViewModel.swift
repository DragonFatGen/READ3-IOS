import Foundation
import LegadoCore
import SwiftUI

@MainActor
final class ExploreViewModel: ObservableObject {
    @Published private(set) var source: BookSource?
    @Published private(set) var categories: [ExploreKind] = []
    @Published private(set) var selectedCategoryIndex: Int?
    @Published private(set) var results: [BookSearchResult] = []
    @Published private(set) var currentPage = 0
    @Published private(set) var isLoadingCategories = false
    @Published private(set) var isLoading = false
    @Published private(set) var isLoadingMore = false
    @Published private(set) var hasMore = false
    @Published private(set) var categoryErrorMessage: String?
    @Published private(set) var errorMessage: String?
    @Published private(set) var loadMoreErrorMessage: String?

    var selectedCategory: ExploreKind? {
        guard let selectedCategoryIndex, categories.indices.contains(selectedCategoryIndex) else {
            return nil
        }
        return categories[selectedCategoryIndex]
    }

    private let service: any BookExploring
    private var categoryCache: [String: CategoryCacheEntry] = [:]
    private var categoryTask: Task<Void, Never>?
    private var requestTask: Task<Void, Never>?
    private var categoryRequestID: UUID?
    private var requestID: UUID?

    init(service: any BookExploring) {
        self.service = service
    }

    deinit {
        categoryTask?.cancel()
        requestTask?.cancel()
    }

    func updateAvailableSources(_ sources: [BookSource]) {
        let available = sources.filter { source in
            guard let value = source.exploreUrl else { return false }
            return !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        guard !available.isEmpty else {
            selectSource(nil)
            return
        }
        if let identity = source?.bookSourceUrl,
           let refreshed = available.first(where: { $0.bookSourceUrl == identity }) {
            if source != refreshed { selectSource(refreshed) }
            return
        }
        selectSource(available[0])
    }

    func selectSource(_ newSource: BookSource?) {
        guard source != newSource else { return }
        cancelCategoryRequest()
        cancelBookRequest()
        source = newSource
        categories = []
        selectedCategoryIndex = nil
        resetBooks()
        categoryErrorMessage = nil
        guard let newSource, let definition = newSource.exploreUrl else { return }

        if let cached = categoryCache[newSource.bookSourceUrl], cached.definition == definition {
            applyCategories(cached.categories, sourceIdentity: newSource.bookSourceUrl)
        } else {
            loadCategories(for: newSource, definition: definition)
        }
    }

    func selectCategory(at index: Int) {
        guard categories.indices.contains(index), categoryURL(categories[index]) != nil else { return }
        guard selectedCategoryIndex != index else { return }
        cancelBookRequest()
        selectedCategoryIndex = index
        resetBooks()
        startPageRequest(page: 1, replacing: true)
    }

    func refreshCategories() {
        guard let source, let definition = source.exploreUrl else { return }
        categoryCache[source.bookSourceUrl] = nil
        cancelCategoryRequest()
        cancelBookRequest()
        categories = []
        selectedCategoryIndex = nil
        resetBooks()
        categoryErrorMessage = nil
        loadCategories(for: source, definition: definition)
    }

    func refreshBooks() async {
        guard selectedCategory != nil else { return }
        cancelBookRequest()
        resetBooks()
        startPageRequest(page: 1, replacing: true)
        let task = requestTask
        await task?.value
    }

    func retryFirstPage() {
        guard selectedCategory != nil else { return }
        cancelBookRequest()
        resetBooks()
        startPageRequest(page: 1, replacing: true)
    }

    func loadMore() {
        guard hasMore, currentPage > 0, !isLoading, !isLoadingMore else { return }
        startPageRequest(page: currentPage + 1, replacing: false)
    }

    func cancelRequests() {
        cancelCategoryRequest()
        cancelBookRequest()
    }

    private func loadCategories(for source: BookSource, definition: String) {
        let id = UUID()
        categoryRequestID = id
        isLoadingCategories = true
        let exploreService = service
        categoryTask = Task { [weak self] in
            do {
                let values = try await exploreService.categories(source: source)
                try Task.checkCancellation()
                guard let self, self.categoryRequestID == id,
                      self.source?.bookSourceUrl == source.bookSourceUrl else { return }
                self.categoryCache[source.bookSourceUrl] = CategoryCacheEntry(
                    definition: definition,
                    categories: values
                )
                self.isLoadingCategories = false
                self.applyCategories(values, sourceIdentity: source.bookSourceUrl)
            } catch is CancellationError {
                guard let self, self.categoryRequestID == id else { return }
                self.isLoadingCategories = false
            } catch {
                guard let self, self.categoryRequestID == id,
                      self.source?.bookSourceUrl == source.bookSourceUrl else { return }
                self.isLoadingCategories = false
                self.categoryErrorMessage = UserFacingError.message(
                    for: error,
                    fallback: "发现分类解析失败"
                )
            }
        }
    }

    private func applyCategories(_ values: [ExploreKind], sourceIdentity: String) {
        guard source?.bookSourceUrl == sourceIdentity else { return }
        categories = values
        categoryErrorMessage = nil
        guard let first = values.indices.first(where: { categoryURL(values[$0]) != nil }) else {
            selectedCategoryIndex = nil
            resetBooks()
            return
        }
        selectedCategoryIndex = nil
        selectCategory(at: first)
    }

    private func startPageRequest(page: Int, replacing: Bool) {
        guard let source, let category = selectedCategory,
              let url = categoryURL(category) else { return }
        guard !isLoading, !isLoadingMore else { return }

        let id = UUID()
        requestID = id
        if replacing { isLoading = true } else { isLoadingMore = true }
        errorMessage = nil
        loadMoreErrorMessage = nil
        let exploreService = service
        requestTask = Task { [weak self] in
            do {
                let values = try await exploreService.explore(
                    source: source,
                    url: url,
                    page: page
                )
                try Task.checkCancellation()
                guard let self, self.requestID == id,
                      self.source?.bookSourceUrl == source.bookSourceUrl,
                      self.selectedCategory?.url == category.url else { return }
                self.finishPage(values, page: page, replacing: replacing)
            } catch is CancellationError {
                guard let self, self.requestID == id else { return }
                self.isLoading = false
                self.isLoadingMore = false
            } catch {
                guard let self, self.requestID == id,
                      self.source?.bookSourceUrl == source.bookSourceUrl else { return }
                self.isLoading = false
                self.isLoadingMore = false
                let message = UserFacingError.message(for: error, fallback: "发现加载失败，请稍后重试")
                if replacing {
                    self.results = []
                    self.errorMessage = message
                    self.hasMore = false
                } else {
                    self.loadMoreErrorMessage = message
                }
            }
        }
    }

    private func finishPage(
        _ values: [BookSearchResult],
        page: Int,
        replacing: Bool
    ) {
        isLoading = false
        isLoadingMore = false
        currentPage = page
        if replacing {
            results = values
            hasMore = !values.isEmpty
            return
        }
        guard !values.isEmpty else {
            hasMore = false
            return
        }

        let existingURLs = Set(results.map(\.bookURL))
        let duplicatesAtBothBoundaries = values.first.map { existingURLs.contains($0.bookURL) } == true &&
            values.last.map { existingURLs.contains($0.bookURL) } == true
        guard !duplicatesAtBothBoundaries else {
            hasMore = false
            return
        }
        // Android appends the complete page when the boundary stop condition is
        // false. It does not remove individual duplicate SearchBook values here.
        results.append(contentsOf: values)
        hasMore = true
    }

    private func resetBooks() {
        results = []
        currentPage = 0
        isLoading = false
        isLoadingMore = false
        hasMore = false
        errorMessage = nil
        loadMoreErrorMessage = nil
    }

    private func cancelCategoryRequest() {
        categoryTask?.cancel()
        categoryTask = nil
        categoryRequestID = nil
        isLoadingCategories = false
    }

    private func cancelBookRequest() {
        requestTask?.cancel()
        requestTask = nil
        requestID = nil
        isLoading = false
        isLoadingMore = false
    }

    private func categoryURL(_ category: ExploreKind) -> String? {
        guard let value = category.url?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty else { return nil }
        return value
    }
}

private struct CategoryCacheEntry {
    let definition: String
    let categories: [ExploreKind]
}
