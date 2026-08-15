import Foundation
import LegadoCore
import SwiftUI

@MainActor
final class ReaderViewModel: ObservableObject {
    @Published private(set) var currentChapterIndex: Int
    @Published private(set) var content: ChapterContentResult?
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var chapterProgress: Double = 0
    @Published private(set) var restorationProgress: Double?

    let source: BookSource
    let book: BookInfoResult
    let chapters: [BookChapterResult]

    private let libraryBookID: String
    private let contentService: any ChapterContentLoading
    private weak var progressStore: (any ReadingProgressStoring)?
    private var loadTask: Task<Void, Never>?
    private var preloadTask: Task<Void, Never>?
    private var saveTask: Task<Void, Never>?
    private var requestID = UUID()

    init(
        source: BookSource,
        book: BookInfoResult,
        libraryBookID: String,
        chapters: [BookChapterResult],
        initialChapterIndex: Int,
        contentService: any ChapterContentLoading,
        progressStore: any ReadingProgressStoring
    ) {
        self.source = source
        self.book = book
        self.libraryBookID = libraryBookID
        self.chapters = chapters
        self.contentService = contentService
        self.progressStore = progressStore
        currentChapterIndex = min(max(initialChapterIndex, 0), max(chapters.count - 1, 0))
        if let saved = progressStore.progress(for: libraryBookID),
           Self.matches(saved, chapter: chapters[safe: currentChapterIndex]) {
            chapterProgress = saved.normalizedChapterProgress
            restorationProgress = saved.normalizedChapterProgress
        }
    }

    deinit {
        loadTask?.cancel()
        preloadTask?.cancel()
        saveTask?.cancel()
    }

    var currentChapter: BookChapterResult? { chapters[safe: currentChapterIndex] }
    var previousChapterAvailable: Bool { currentChapterIndex > 0 }
    var nextChapterAvailable: Bool { currentChapterIndex + 1 < chapters.count }

    func loadInitialChapter() {
        guard content == nil, !isLoading else { return }
        loadCurrentChapter()
    }

    func retry() { loadCurrentChapter() }

    func reloadCurrentChapter() { loadCurrentChapter(policy: .reloadIgnoringCache) }

    func goToPreviousChapter() {
        guard previousChapterAvailable else { return }
        switchChapter(to: currentChapterIndex - 1)
    }

    func goToNextChapter() {
        guard nextChapterAvailable else { return }
        switchChapter(to: currentChapterIndex + 1)
    }

    func goToChapter(at index: Int) {
        guard chapters.indices.contains(index), index != currentChapterIndex else { return }
        switchChapter(to: index)
    }

    func updateProgress(_ value: Double) {
        chapterProgress = min(max(value, 0), 1)
        scheduleProgressSave()
    }

    func consumeRestorationProgress() -> Double? {
        defer { restorationProgress = nil }
        return restorationProgress
    }

    func saveProgressNow() {
        saveTask?.cancel()
        persistProgress()
    }

    func cancel() {
        loadTask?.cancel()
        preloadTask?.cancel()
        saveProgressNow()
    }

    private func switchChapter(to index: Int) {
        saveProgressNow()
        loadTask?.cancel()
        preloadTask?.cancel()
        currentChapterIndex = index
        chapterProgress = 0
        restorationProgress = 0
        content = nil
        errorMessage = nil
        loadCurrentChapter()
    }

    private func loadCurrentChapter(policy: ContentLoadPolicy = .cacheFirst) {
        guard let chapter = currentChapter else { return }
        loadTask?.cancel()
        let id = UUID()
        requestID = id
        isLoading = true
        errorMessage = nil
        let source = source
        let book = book
        let service = contentService
        loadTask = Task { [weak self] in
            do {
                let result = try await service.loadContent(
                    source: source,
                    book: book,
                    chapter: chapter,
                    policy: policy
                )
                try Task.checkCancellation()
                guard let self, self.requestID == id,
                      self.currentChapter?.url == chapter.url else { return }
                self.content = result
                self.isLoading = false
                self.persistProgress()
                self.preloadAdjacentChapters(around: self.currentChapterIndex)
            } catch is CancellationError {
                guard let self, self.requestID == id else { return }
                self.isLoading = false
            } catch {
                guard let self, self.requestID == id, !Task.isCancelled else { return }
                self.isLoading = false
                self.errorMessage = UserFacingError.message(
                    for: error, fallback: "无法加载章节正文"
                )
            }
        }
    }

    private func preloadAdjacentChapters(around index: Int) {
        preloadTask?.cancel()
        let candidates = [index + 1, index - 1].compactMap { chapters[safe: $0] }
        guard !candidates.isEmpty else { return }
        let source = source
        let book = book
        let service = contentService
        preloadTask = Task(priority: .utility) {
            for chapter in candidates {
                guard !Task.isCancelled else { return }
                _ = try? await service.loadContent(
                    source: source,
                    book: book,
                    chapter: chapter,
                    policy: .cacheFirst
                )
            }
        }
    }

    private func scheduleProgressSave() {
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            do { try await Task.sleep(for: .milliseconds(700)) }
            catch { return }
            guard !Task.isCancelled else { return }
            self?.persistProgress()
        }
    }

    private func persistProgress() {
        guard let chapter = currentChapter else { return }
        progressStore?.saveProgress(
            ReadingProgress(
                lastChapterURL: chapter.url,
                lastChapterName: chapter.name,
                lastChapterIndex: currentChapterIndex,
                chapterProgress: chapterProgress,
                chapterCount: chapters.count,
                lastReadAt: Date()
            ),
            for: libraryBookID
        )
    }

    private static func matches(_ progress: ReadingProgress, chapter: BookChapterResult?) -> Bool {
        guard let chapter else { return false }
        return progress.lastChapterURL == chapter.url || progress.lastChapterIndex == chapter.index
    }
}

private extension Collection {
    subscript(safe index: Index) -> Element? { indices.contains(index) ? self[index] : nil }
}
