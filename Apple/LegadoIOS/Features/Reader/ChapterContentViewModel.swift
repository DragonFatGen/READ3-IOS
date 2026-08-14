import Foundation
import LegadoCore
import SwiftUI

@MainActor
final class ChapterContentViewModel: ObservableObject {
    @Published private(set) var content: ChapterContentResult?
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?

    let chapter: BookChapterResult
    private let source: BookSource
    private let book: BookInfoResult
    private let service: any ChapterContentLoading
    private var requestID: UUID?

    init(
        source: BookSource,
        book: BookInfoResult,
        chapter: BookChapterResult,
        service: any ChapterContentLoading
    ) {
        self.source = source
        self.book = book
        self.chapter = chapter
        self.service = service
    }

    func loadIfNeeded() async {
        guard content == nil, !isLoading else { return }
        await load()
    }

    func retry() async { await load() }

    private func load() async {
        let id = UUID()
        requestID = id
        isLoading = true
        errorMessage = nil
        do {
            let value = try await service.loadContent(
                source: source,
                book: book,
                chapter: chapter
            )
            try Task.checkCancellation()
            guard requestID == id else { return }
            content = value
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
            errorMessage = UserFacingError.message(for: error, fallback: "无法加载章节正文")
        }
    }
}
