import Foundation
import LegadoCore
import SwiftUI

@MainActor
final class BookDetailViewModel: ObservableObject {
    @Published private(set) var bookInfo: BookInfoResult?
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?

    let searchResult: BookSearchResult
    private let source: BookSource
    private let service: any BookInfoLoading
    private var requestID: UUID?

    init(source: BookSource, searchResult: BookSearchResult, service: any BookInfoLoading) {
        self.source = source
        self.searchResult = searchResult
        self.service = service
    }

    func loadIfNeeded() async {
        guard bookInfo == nil, !isLoading else { return }
        await load()
    }

    func retry() async { await load() }

    private func load() async {
        let id = UUID()
        requestID = id
        isLoading = true
        errorMessage = nil
        do {
            let value = try await service.loadBookInfo(source: source, book: searchResult)
            try Task.checkCancellation()
            guard requestID == id else { return }
            bookInfo = value
            isLoading = false
        } catch is CancellationError {
            guard requestID == id else { return }
            isLoading = false
        } catch {
            guard requestID == id else { return }
            guard !Task.isCancelled else {
                isLoading = false
                return
            }
            isLoading = false
            errorMessage = UserFacingError.message(for: error, fallback: "无法加载书籍详情")
        }
    }
}
