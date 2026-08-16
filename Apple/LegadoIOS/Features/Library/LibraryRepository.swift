import Combine
import Foundation
import LegadoCore

@MainActor
protocol ReadingProgressStoring: AnyObject {
    func progress(for bookID: String) -> ReadingProgress?
    func saveProgress(_ progress: ReadingProgress, for bookID: String)
}

@MainActor
final class LibraryRepository: ObservableObject, ReadingProgressStoring {
    @Published private(set) var books: [LibraryBook] = []

    private let defaults: UserDefaults
    private let storageKey: String
    private var progressByBookID: [String: ReadingProgress] = [:]

    init(defaults: UserDefaults = .standard, storageKey: String = "library.books.v1") {
        self.defaults = defaults
        self.storageKey = storageKey
        load()
    }

    func add(source: BookSource, bookInfo: BookInfoResult) {
        let value = LibraryBook(source: source, bookInfo: bookInfo)
        if let index = books.firstIndex(where: { $0.id == value.id }) {
            var refreshed = value
            refreshed.addedAt = books[index].addedAt
            refreshed.lastReadAt = books[index].lastReadAt
            refreshed.progress = books[index].progress ?? progressByBookID[value.id]
            refreshed.lastCheckedAt = books[index].lastCheckedAt
            refreshed.lastKnownChapterCount = books[index].lastKnownChapterCount
            refreshed.lastKnownLatestChapterURL = books[index].lastKnownLatestChapterURL
            refreshed.lastKnownLatestChapterName = books[index].lastKnownLatestChapterName
            refreshed.updateCount = books[index].updateCount
            refreshed.lastUpdateError = books[index].lastUpdateError
            books[index] = refreshed
        } else {
            books.insert(value, at: 0)
        }
        persist()
    }

    func contains(sourceURL: String, bookURL: String) -> Bool {
        books.contains { $0.id == LibraryBook.identifier(sourceURL: sourceURL, bookURL: bookURL) }
    }

    func remove(bookID: String) {
        books.removeAll { $0.id == bookID }
        progressByBookID.removeValue(forKey: bookID)
        persist()
    }

    func progress(for bookID: String) -> ReadingProgress? {
        books.first(where: { $0.id == bookID })?.progress ?? progressByBookID[bookID]
    }

    func saveProgress(_ progress: ReadingProgress, for bookID: String) {
        progressByBookID[bookID] = progress
        if let index = books.firstIndex(where: { $0.id == bookID }) {
            books[index].progress = progress
            books[index].lastReadAt = progress.lastReadAt
            Self.markRead(&books[index], chapterIndex: progress.lastChapterIndex)
        }
        persist()
    }

    func applyUpdateCheck(bookID: String, result: BookUpdateResult) {
        guard let index = books.firstIndex(where: { $0.id == bookID }) else { return }
        books[index].lastCheckedAt = result.checkedAt
        books[index].lastKnownChapterCount = result.chapterCount
        books[index].lastKnownLatestChapterURL = result.latestChapterURL
        books[index].lastKnownLatestChapterName = result.latestChapterName
        books[index].updateCount = max(books[index].updateCount + result.newChapterCount, 0)
        books[index].lastUpdateError = nil
        persist()
    }

    func recordUpdateFailure(bookID: String, message: String) {
        guard let index = books.firstIndex(where: { $0.id == bookID }) else { return }
        books[index].lastUpdateError = message
        persist()
    }

    func markRead(bookID: String, chapterIndex: Int) {
        guard let index = books.firstIndex(where: { $0.id == bookID }) else { return }
        Self.markRead(&books[index], chapterIndex: chapterIndex)
        persist()
    }

    func referenceCount(forSourceIdentity identity: String) -> Int {
        books.filter { $0.source.bookSourceUrl == identity || $0.sourceURL == identity }.count
    }

    private static func markRead(_ book: inout LibraryBook, chapterIndex: Int) {
        guard book.updateCount > 0, let chapterCount = book.lastKnownChapterCount else { return }
        let remainingAfterChapter = max(chapterCount - chapterIndex - 1, 0)
        book.updateCount = min(book.updateCount, remainingAfterChapter)
    }

    private func load() {
        guard let data = defaults.data(forKey: storageKey),
              let decoded = try? JSONDecoder().decode([LibraryBook].self, from: data) else { return }
        books = decoded
        progressByBookID = decoded.reduce(into: [:]) { values, book in
            values[book.id] = book.progress
        }
        if let progressData = defaults.data(forKey: "\(storageKey).progress"),
           let decodedProgress = try? JSONDecoder().decode(
               [String: ReadingProgress].self, from: progressData
           ) {
            progressByBookID.merge(decodedProgress) { _, newer in newer }
        }
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(books) else { return }
        defaults.set(data, forKey: storageKey)
        if let progressData = try? JSONEncoder().encode(progressByBookID) {
            defaults.set(progressData, forKey: "\(storageKey).progress")
        }
    }
}
