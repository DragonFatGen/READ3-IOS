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
    @Published private(set) var layoutMode: ReaderLayoutMode
    @Published private(set) var pages: [ReaderPage] = []
    @Published private(set) var currentPageIndex = 0
    @Published private(set) var isPaginating = false
    @Published private(set) var scrollRestorationID = 0
    @Published private(set) var bookmarks: [ReaderBookmark] = []

    let source: BookSource
    let book: BookInfoResult
    let chapters: [BookChapterResult]

    private let libraryBookID: String
    private let contentService: any ChapterContentLoading
    private let paginator: any ReaderPaginating
    private weak var progressStore: (any ReadingProgressStoring)?
    private weak var bookmarkStore: (any BookmarkStoring)?
    private weak var speechController: ReaderSpeechController?
    private var loadTask: Task<Void, Never>?
    private var preloadTask: Task<Void, Never>?
    private var saveTask: Task<Void, Never>?
    private var paginationTask: Task<Void, Never>?
    private var requestID = UUID()
    private var paginationID = UUID()
    private var paginationConfiguration: PaginationConfiguration?
    private var chapterEntryPosition: ChapterEntryPosition = .restore

    init(
        source: BookSource,
        book: BookInfoResult,
        libraryBookID: String,
        chapters: [BookChapterResult],
        initialChapterIndex: Int,
        contentService: any ChapterContentLoading,
        progressStore: any ReadingProgressStoring,
        bookmarkStore: (any BookmarkStoring)? = nil,
        paginator: any ReaderPaginating = TextKitReaderPaginator(),
        layoutMode: ReaderLayoutMode = .scroll
    ) {
        self.source = source
        self.book = book
        self.libraryBookID = libraryBookID
        self.chapters = chapters
        self.contentService = contentService
        self.progressStore = progressStore
        self.bookmarkStore = bookmarkStore
        self.paginator = paginator
        self.layoutMode = layoutMode
        currentChapterIndex = min(max(initialChapterIndex, 0), max(chapters.count - 1, 0))
        if let saved = progressStore.progress(for: libraryBookID),
           Self.matches(saved, chapter: chapters[safe: currentChapterIndex]) {
            chapterProgress = saved.normalizedChapterProgress
            restorationProgress = saved.normalizedChapterProgress
        }
        bookmarks = bookmarkStore?.bookmarks(for: libraryBookID) ?? []
    }

    deinit {
        loadTask?.cancel()
        preloadTask?.cancel()
        saveTask?.cancel()
        paginationTask?.cancel()
    }

    var currentChapter: BookChapterResult? { chapters[safe: currentChapterIndex] }
    var libraryBookIdentity: String { libraryBookID }
    var previousChapterAvailable: Bool { currentChapterIndex > 0 }
    var nextChapterAvailable: Bool { currentChapterIndex + 1 < chapters.count }
    var currentNormalizedProgress: Double { chapterProgress }
    var isCurrentPositionBookmarked: Bool { matchingCurrentBookmark() != nil }
    var pageProgressText: String? {
        guard layoutMode == .paged, !pages.isEmpty else { return nil }
        return "\(currentPageIndex + 1) / \(pages.count)"
    }

    func loadInitialChapter() {
        guard content == nil, !isLoading else { return }
        loadCurrentChapter()
    }

    func retry() { loadCurrentChapter() }

    func reloadCurrentChapter() { loadCurrentChapter(policy: .reloadIgnoringCache) }

    func setLayoutMode(_ mode: ReaderLayoutMode) {
        guard layoutMode != mode else { return }
        if layoutMode == .paged { updateProgressFromCurrentPage() }
        layoutMode = mode
        if mode == .paged {
            requestPagination(entryPosition: .restore)
        } else {
            paginationTask?.cancel()
            isPaginating = false
            pages = []
            restorationProgress = chapterProgress
            scrollRestorationID += 1
        }
    }

    func updatePaginationConfiguration(_ configuration: PaginationConfiguration) {
        guard configuration.size.width > 1, configuration.size.height > 1,
              paginationConfiguration != configuration else { return }
        if layoutMode == .paged { updateProgressFromCurrentPage() }
        paginationConfiguration = configuration
        if layoutMode == .paged { requestPagination(entryPosition: .restore) }
    }

    func goToPreviousChapter() {
        guard previousChapterAvailable else { return }
        speechController?.readerWillNavigate(self)
        switchChapter(to: currentChapterIndex - 1, entryPosition: .start)
    }

    func goToNextChapter() {
        guard nextChapterAvailable else { return }
        speechController?.readerWillNavigate(self)
        switchChapter(to: currentChapterIndex + 1, entryPosition: .start)
    }

    func goToChapter(at index: Int) {
        guard chapters.indices.contains(index) else { return }
        guard index != currentChapterIndex else { return }
        speechController?.readerWillNavigate(self)
        switchChapter(to: index, entryPosition: .start)
    }

    func selectPage(_ index: Int) {
        guard pages.indices.contains(index), index != currentPageIndex else { return }
        currentPageIndex = index
        updateProgressFromCurrentPage()
    }

    func turnPageForward() {
        guard layoutMode == .paged, !pages.isEmpty else { return }
        if currentPageIndex < pages.count - 1 {
            selectPage(currentPageIndex + 1)
        } else if nextChapterAvailable {
            speechController?.readerWillNavigate(self)
            switchChapter(to: currentChapterIndex + 1, entryPosition: .start)
        }
    }

    func turnPageBackward() {
        guard layoutMode == .paged, !pages.isEmpty else { return }
        if currentPageIndex > 0 {
            selectPage(currentPageIndex - 1)
        } else if previousChapterAvailable {
            speechController?.readerWillNavigate(self)
            switchChapter(to: currentChapterIndex - 1, entryPosition: .end)
        }
    }

    func updateProgress(_ value: Double) {
        chapterProgress = min(max(value, 0), 1)
        scheduleProgressSave()
    }

    func seek(to progress: Double) {
        let target = min(max(progress, 0), 1)
        chapterProgress = target
        if layoutMode == .paged, !pages.isEmpty {
            let lastIndex = max(pages.count - 1, 0)
            currentPageIndex = min(max(Int((target * Double(lastIndex)).rounded()), 0), lastIndex)
            updateProgressFromCurrentPage()
        } else {
            restorationProgress = target
            scrollRestorationID += 1
        }
        saveProgressNow()
        speechController?.readerDidSeek(self)
    }

    func toggleBookmark() {
        guard let chapter = currentChapter, let store = bookmarkStore else { return }
        if let existing = matchingCurrentBookmark() {
            store.remove(id: existing.id)
        } else {
            store.add(ReaderBookmark(
                id: UUID(),
                bookID: libraryBookID,
                sourceIdentity: source.bookSourceUrl,
                bookIdentity: book.bookURL,
                chapterIndex: currentChapterIndex,
                chapterURL: chapter.url,
                chapterName: chapter.name,
                chapterProgress: chapterProgress,
                previewText: BookmarkPreviewBuilder.makePreview(
                    content: content?.content ?? "",
                    normalizedProgress: chapterProgress
                ),
                createdAt: Date()
            ))
        }
        refreshBookmarks()
    }

    func removeBookmark(id: UUID) {
        bookmarkStore?.remove(id: id)
        refreshBookmarks()
    }

    func goToBookmark(_ bookmark: ReaderBookmark) {
        guard bookmark.bookID == libraryBookID,
              chapters.indices.contains(bookmark.chapterIndex) else { return }
        let progress = min(max(bookmark.chapterProgress, 0), 1)
        if bookmark.chapterIndex == currentChapterIndex {
            seek(to: progress)
        } else {
            speechController?.readerWillNavigate(self)
            switchChapter(
                to: bookmark.chapterIndex,
                entryPosition: .restore,
                targetProgress: progress
            )
        }
    }

    func consumeRestorationProgress() -> Double? {
        defer { restorationProgress = nil }
        return restorationProgress
    }

    func saveProgressNow() {
        saveTask?.cancel()
        persistProgress()
    }

    func cancel(persistProgress shouldPersistProgress: Bool = true) {
        loadTask?.cancel()
        preloadTask?.cancel()
        paginationTask?.cancel()
        if shouldPersistProgress { saveProgressNow() }
        else { saveTask?.cancel() }
    }

    func attachSpeechController(_ controller: ReaderSpeechController) {
        speechController = controller
    }

    func advanceChapterForSpeech() {
        guard nextChapterAvailable else { return }
        switchChapter(to: currentChapterIndex + 1, entryPosition: .start)
    }

    func synchronizeToSpeech(chapterIndex: Int, normalizedProgress: Double) {
        let safeProgress = min(max(normalizedProgress, 0), 1)
        guard chapters.indices.contains(chapterIndex) else { return }
        if chapterIndex == currentChapterIndex {
            chapterProgress = safeProgress
            restorationProgress = safeProgress
            if content != nil { speechController?.readerDidLoadContent(self) }
        } else {
            switchChapter(
                to: chapterIndex,
                entryPosition: .restore,
                targetProgress: safeProgress
            )
        }
    }

    func updateProgressFromSpeech(utf16Offset: Int) {
        guard let text = content?.content else { return }
        let total = max(text.utf16.count, 1)
        chapterProgress = min(max(Double(utf16Offset) / Double(total), 0), 1)
        if layoutMode == .paged, !pages.isEmpty {
            if let page = pages.firstIndex(where: { $0.utf16Range.contains(utf16Offset) }) {
                currentPageIndex = page
            } else if utf16Offset >= total {
                currentPageIndex = pages.count - 1
            }
        }
        scheduleProgressSave()
    }

    private func switchChapter(
        to index: Int,
        entryPosition: ChapterEntryPosition,
        targetProgress: Double? = nil
    ) {
        saveProgressNow()
        loadTask?.cancel()
        preloadTask?.cancel()
        paginationTask?.cancel()
        currentChapterIndex = index
        chapterEntryPosition = entryPosition
        chapterProgress = targetProgress.map { min(max($0, 0), 1) }
            ?? (entryPosition == .end ? 1 : 0)
        restorationProgress = chapterProgress
        pages = []
        currentPageIndex = 0
        isPaginating = false
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
                if self.layoutMode == .paged {
                    self.requestPagination(entryPosition: self.chapterEntryPosition)
                }
                self.speechController?.readerDidLoadContent(self)
            } catch is CancellationError {
                guard let self, self.requestID == id else { return }
                self.isLoading = false
            } catch {
                guard let self, self.requestID == id, !Task.isCancelled else { return }
                self.isLoading = false
                self.errorMessage = UserFacingError.message(
                    for: error, fallback: "无法加载章节正文"
                )
                self.speechController?.readerDidFailLoadingContent(self)
            }
        }
    }

    private func requestPagination(entryPosition: ChapterEntryPosition) {
        guard layoutMode == .paged,
              let text = content?.content,
              let configuration = paginationConfiguration else { return }
        paginationTask?.cancel()
        let id = UUID()
        paginationID = id
        let chapterURL = currentChapter?.url
        let progress = chapterProgress
        let paginator = paginator
        isPaginating = true
        paginationTask = Task { [weak self] in
            let generated = await paginator.paginate(text: text, configuration: configuration)
            guard !Task.isCancelled, let self,
                  self.paginationID == id,
                  self.currentChapter?.url == chapterURL,
                  self.paginationConfiguration == configuration,
                  self.layoutMode == .paged else { return }
            let safePages = generated.isEmpty
                ? [ReaderPage(index: 0, utf16Range: 0..<text.utf16.count, text: text)]
                : generated
            self.pages = safePages
            let lastIndex = max(safePages.count - 1, 0)
            switch entryPosition {
            case .start:
                self.currentPageIndex = 0
            case .end:
                self.currentPageIndex = lastIndex
            case .restore:
                self.currentPageIndex = min(
                    max(Int((progress * Double(lastIndex)).rounded()), 0),
                    lastIndex
                )
            }
            self.chapterEntryPosition = .restore
            self.isPaginating = false
            self.updateProgressFromCurrentPage()
        }
    }

    private func updateProgressFromCurrentPage() {
        guard !pages.isEmpty else { return }
        chapterProgress = pages.count == 1
            ? 0
            : Double(currentPageIndex) / Double(pages.count - 1)
        scheduleProgressSave()
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

    private func matchingCurrentBookmark() -> ReaderBookmark? {
        guard let chapter = currentChapter else { return nil }
        let chapterBookmarks = bookmarks.filter {
            $0.chapterURL == chapter.url || $0.chapterIndex == currentChapterIndex
        }
        return chapterBookmarks.min { lhs, rhs in
            abs(lhs.chapterProgress - chapterProgress) < abs(rhs.chapterProgress - chapterProgress)
        }.flatMap { bookmark in
            let nearby = abs(bookmark.chapterProgress - chapterProgress)
                <= ReaderBookmarkMetrics.positionTolerance
            return nearby ? bookmark : nil
        }
    }

    private func refreshBookmarks() {
        bookmarks = bookmarkStore?.bookmarks(for: libraryBookID) ?? []
    }

    private static func matches(_ progress: ReadingProgress, chapter: BookChapterResult?) -> Bool {
        guard let chapter else { return false }
        return progress.lastChapterURL == chapter.url || progress.lastChapterIndex == chapter.index
    }
}

private extension Collection {
    subscript(safe index: Index) -> Element? { indices.contains(index) ? self[index] : nil }
}
