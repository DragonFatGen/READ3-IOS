import Foundation
import LegadoCore
import SwiftUI

@MainActor
final class TOCViewModel: ObservableObject {
    @Published private(set) var chapters: [BookChapterResult] = []
    @Published private(set) var isLoading = false
    @Published private(set) var hasLoaded = false
    @Published private(set) var errorMessage: String?

    private let source: BookSource
    private let book: BookInfoResult
    private let service: any TOCLoading
    private var requestID: UUID?

    init(source: BookSource, book: BookInfoResult, service: any TOCLoading) {
        self.source = source
        self.book = book
        self.service = service
    }

    func loadIfNeeded() async {
        guard !hasLoaded, !isLoading else { return }
        await load()
    }

    func retry() async { await load() }

    private func load() async {
        let id = UUID()
        requestID = id
        isLoading = true
        errorMessage = nil
        do {
            let values = try await service.loadTOC(source: source, book: book)
            try Task.checkCancellation()
            guard requestID == id else { return }
            chapters = values
            hasLoaded = true
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
            chapters = []
            isLoading = false
            errorMessage = UserFacingError.message(for: error, fallback: "无法加载章节目录")
        }
    }
}
