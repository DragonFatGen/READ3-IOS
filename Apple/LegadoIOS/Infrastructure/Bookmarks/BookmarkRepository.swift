import Foundation

@MainActor
protocol BookmarkStoring: AnyObject {
    func bookmarks(for bookID: String) -> [ReaderBookmark]
    func add(_ bookmark: ReaderBookmark)
    func remove(id: UUID)
    func removeAll(for bookID: String)
}

@MainActor
final class BookmarkRepository: BookmarkStoring {
    private let fileURL: URL
    private var storedBookmarks: [ReaderBookmark]
    private(set) var lastPersistenceError: Error?

    init(fileURL: URL? = nil) {
        self.fileURL = fileURL ?? Self.defaultFileURL()
        storedBookmarks = Self.load(from: self.fileURL)
    }

    func bookmarks(for bookID: String) -> [ReaderBookmark] {
        storedBookmarks
            .filter { $0.bookID == bookID }
            .sorted {
                if $0.chapterIndex != $1.chapterIndex {
                    return $0.chapterIndex < $1.chapterIndex
                }
                if $0.chapterProgress != $1.chapterProgress {
                    return $0.chapterProgress < $1.chapterProgress
                }
                return $0.createdAt < $1.createdAt
            }
    }

    func add(_ bookmark: ReaderBookmark) {
        storedBookmarks.append(bookmark)
        persist()
    }

    func remove(id: UUID) {
        storedBookmarks.removeAll { $0.id == id }
        persist()
    }

    func removeAll(for bookID: String) {
        storedBookmarks.removeAll { $0.bookID == bookID }
        persist()
    }

    private func persist() {
        do {
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.sortedKeys]
            try encoder.encode(storedBookmarks).write(to: fileURL, options: .atomic)
            lastPersistenceError = nil
        } catch {
            // Persistence is an enhancement: retain the in-memory bookmarks so reading is uninterrupted.
            lastPersistenceError = error
        }
    }

    private static func load(from fileURL: URL) -> [ReaderBookmark] {
        guard let data = try? Data(contentsOf: fileURL) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode([ReaderBookmark].self, from: data)) ?? []
    }

    private static func defaultFileURL() -> URL {
        let base = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        )[0]
        return base
            .appendingPathComponent("ReaderBookmarks", isDirectory: true)
            .appendingPathComponent("bookmarks.json")
    }
}
