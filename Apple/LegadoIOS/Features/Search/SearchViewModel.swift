import Foundation
import LegadoCore
import SwiftUI

@MainActor
final class SearchViewModel: ObservableObject {
    @Published var query = ""
    @Published private(set) var results: [BookSearchResult] = []
    @Published private(set) var isLoading = false
    @Published private(set) var hasSearched = false
    @Published private(set) var errorMessage: String?

    private let source: BookSource
    private let service: any BookSearching
    private var searchTask: Task<Void, Never>?
    private var requestID: UUID?

    init(source: BookSource, service: any BookSearching) {
        self.source = source
        self.service = service
    }

    deinit { searchTask?.cancel() }

    func search() {
        let keyword = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !keyword.isEmpty else { return }
        searchTask?.cancel()
        let id = UUID()
        requestID = id
        isLoading = true
        hasSearched = true
        errorMessage = nil
        let selectedSource = source
        let searchService = service
        searchTask = Task { [weak self] in
            do {
                let values = try await searchService.search(
                    source: selectedSource,
                    keyword: keyword
                )
                try Task.checkCancellation()
                guard let self, self.requestID == id else { return }
                self.results = values
                self.isLoading = false
            } catch is CancellationError {
                guard let self, self.requestID == id else { return }
                self.isLoading = false
            } catch {
                guard let self, self.requestID == id else { return }
                guard !Task.isCancelled else {
                    self.isLoading = false
                    return
                }
                self.results = []
                self.isLoading = false
                self.errorMessage = UserFacingError.message(for: error, fallback: "搜索失败，请稍后重试")
            }
        }
    }

    func cancelSearch() {
        searchTask?.cancel()
    }
}
