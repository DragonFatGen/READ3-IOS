import Foundation
import LegadoCore

enum CachedContentError: Error, LocalizedError, Sendable {
    case unavailableOffline(technicalMessage: String)

    var errorDescription: String? {
        switch self {
        case .unavailableOffline:
            "当前章节尚未缓存，无法离线阅读"
        }
    }
}

actor CachedContentService: ChapterContentLoading {
    private let cache: any ChapterContentCache
    private let upstream: any ChapterContentLoading
    private var inFlight: [ChapterCacheKey: Task<ChapterContentResult, Error>] = [:]

    init(cache: any ChapterContentCache, upstream: any ChapterContentLoading) {
        self.cache = cache
        self.upstream = upstream
    }

    func loadContent(
        source: BookSource,
        book: BookInfoResult,
        chapter: BookChapterResult,
        policy: ContentLoadPolicy
    ) async throws -> ChapterContentResult {
        let key = ChapterCacheKey(source: source, book: book, chapter: chapter)
        if policy == .cacheFirst, let cached = await cache.content(for: key) {
            return cached.result
        }
        if let existing = inFlight[key] {
            do {
                return try await existing.value
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                throw CachedContentError.unavailableOffline(
                    technicalMessage: error.localizedDescription
                )
            }
        }

        let upstream = upstream
        let task = Task<ChapterContentResult, Error> {
            try await upstream.loadContent(
                source: source,
                book: book,
                chapter: chapter,
                policy: .reloadIgnoringCache
            )
        }
        inFlight[key] = task
        do {
            let result = try await task.value
            let entry = ChapterContentCacheEntry(
                key: key,
                chapterName: chapter.name,
                content: result.content,
                chapterURL: result.chapterURL,
                cachedAt: Date()
            )
            // Caching is an enhancement. A successful Core result must remain
            // readable even if the cache directory cannot be written.
            try? await cache.save(entry)
            inFlight[key] = nil
            return result
        } catch is CancellationError {
            inFlight[key] = nil
            throw CancellationError()
        } catch {
            inFlight[key] = nil
            throw CachedContentError.unavailableOffline(
                technicalMessage: error.localizedDescription
            )
        }
    }
}
