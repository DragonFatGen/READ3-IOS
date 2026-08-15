import Foundation
import LegadoCore
import XCTest
@testable import LegadoIOS

@MainActor
final class ChapterContentCacheTests: XCTestCase {
    func testMemoryAndDiskHits() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let key = testKey(index: 0)
        let entry = testEntry(index: 0)
        let first = FileChapterContentCache(directory: directory)
        try await first.save(entry)

        let files = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        XCTAssertEqual(files.count, 1)
        try FileManager.default.removeItem(at: files[0])
        let memoryValue = await first.content(for: key)
        XCTAssertEqual(memoryValue, entry, "L1 should survive removal of its disk file")

        try await first.save(entry)
        let second = FileChapterContentCache(directory: directory)
        let diskValue = await second.content(for: key)
        XCTAssertEqual(diskValue, entry, "A fresh cache actor should read L2")
    }

    func testCorruptedDiskEntryFallsBackToUpstream() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let disk = FileChapterContentCache(directory: directory)
        try await disk.save(testEntry(index: 0))
        let file = try XCTUnwrap(
            FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil).first
        )
        try Data("not-json".utf8).write(to: file)

        let upstream = CountingContentService()
        let service = CachedContentService(
            cache: FileChapterContentCache(directory: directory),
            upstream: upstream
        )
        let result = try await load(service, index: 0)
        XCTAssertEqual(result.content, "network 0")
        let callCount = await upstream.callCount
        XCTAssertEqual(callCount, 1)
    }

    func testCacheMissSavesAndLaterHitAvoidsUpstream() async throws {
        let cache = MemoryChapterCache()
        let upstream = CountingContentService()
        let service = CachedContentService(cache: cache, upstream: upstream)

        let first = try await load(service, index: 0)
        let second = try await load(service, index: 0)
        XCTAssertEqual(first.content, "network 0")
        XCTAssertEqual(second.content, "network 0")
        let callCount = await upstream.callCount
        let cached = await cache.content(for: testKey(index: 0))
        XCTAssertEqual(callCount, 1)
        XCTAssertNotNil(cached)
    }

    func testProductionFailureReportsOfflineCacheMiss() async {
        let service = CachedContentService(
            cache: MemoryChapterCache(),
            upstream: CountingContentService(shouldFail: true)
        )
        do {
            _ = try await load(service, index: 0)
            XCTFail("Expected an offline cache miss")
        } catch let error as CachedContentError {
            XCTAssertEqual(error.localizedDescription, "当前章节尚未缓存，无法离线阅读")
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testForceReloadBypassesAndOverwritesCache() async throws {
        let cache = MemoryChapterCache(entries: [testKey(index: 0): testEntry(index: 0, content: "old")])
        let upstream = CountingContentService()
        let service = CachedContentService(cache: cache, upstream: upstream)

        let cachedResult = try await load(service, index: 0)
        let reloaded = try await load(service, index: 0, policy: .reloadIgnoringCache)
        XCTAssertEqual(cachedResult.content, "old")
        XCTAssertEqual(reloaded.content, "network 0")
        let callCount = await upstream.callCount
        let cached = await cache.content(for: testKey(index: 0))
        XCTAssertEqual(callCount, 1)
        XCTAssertEqual(cached?.content, "network 0")
    }

    func testConcurrentDuplicateRequestsShareUpstreamTask() async throws {
        let upstream = CountingContentService(delay: .milliseconds(40))
        let service = CachedContentService(cache: MemoryChapterCache(), upstream: upstream)
        let source = testSource()
        let book = testBookInfo()
        let chapter = testChapter()
        async let first = service.loadContent(
            source: source, book: book, chapter: chapter, policy: .cacheFirst
        )
        async let second = service.loadContent(
            source: source, book: book, chapter: chapter, policy: .cacheFirst
        )
        _ = try await (first, second)
        let callCount = await upstream.callCount
        XCTAssertEqual(callCount, 1)
    }

    func testPreloadedEntryIsUsedByActiveLoad() async throws {
        let upstream = CountingContentService()
        let service = CachedContentService(cache: MemoryChapterCache(), upstream: upstream)
        _ = try await load(service, index: 1)
        _ = try await load(service, index: 1)
        let callCount = await upstream.callCount
        XCTAssertEqual(callCount, 1)
    }

    func testCacheWriteFailureDoesNotFailReading() async throws {
        let service = CachedContentService(
            cache: MemoryChapterCache(failsWrites: true),
            upstream: CountingContentService()
        )
        let result = try await load(service, index: 0)
        XCTAssertEqual(result.content, "network 0")
    }

    func testCapacityCleanup() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let cache = FileChapterContentCache(
            directory: directory,
            configuration: ChapterCacheConfiguration(
                maximumDiskBytes: 1_100,
                targetDiskBytes: 600,
                memoryEntryLimit: 2
            )
        )
        for index in 0..<4 {
            try await cache.save(testEntry(index: index, content: String(repeating: "文", count: 300)))
        }
        let files = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        XCTAssertLessThan(files.count, 4)
    }

    func testRemoveBookClearsItsChapterEntries() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let cache = FileChapterContentCache(directory: directory)
        try await cache.save(testEntry(index: 0))
        try await cache.save(testEntry(index: 1))
        await cache.removeAll(for: testKey(index: 0).bookKey)
        let removed = await cache.content(for: testKey(index: 0))
        XCTAssertNil(removed)
    }

    private func load(
        _ service: any ChapterContentLoading,
        index: Int,
        policy: ContentLoadPolicy = .cacheFirst
    ) async throws -> ChapterContentResult {
        try await service.loadContent(
            source: testSource(), book: testBookInfo(), chapter: testChapter(index: index), policy: policy
        )
    }

    private func testKey(index: Int) -> ChapterCacheKey {
        ChapterCacheKey(source: testSource(), book: testBookInfo(), chapter: testChapter(index: index))
    }

    private func testEntry(index: Int, content: String? = nil) -> ChapterContentCacheEntry {
        ChapterContentCacheEntry(
            key: testKey(index: index),
            chapterName: testChapter(index: index).name,
            content: content ?? "cached \(index)",
            chapterURL: testChapter(index: index).url,
            cachedAt: Date(timeIntervalSince1970: Double(index + 1))
        )
    }

    private func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("ChapterContentCacheTests-\(UUID().uuidString)", isDirectory: true)
    }
}

private enum TestContentError: Error, Sendable { case failed }

private actor CountingContentService: ChapterContentLoading {
    private(set) var callCount = 0
    private let delay: Duration
    private let shouldFail: Bool

    init(delay: Duration = .zero, shouldFail: Bool = false) {
        self.delay = delay
        self.shouldFail = shouldFail
    }

    func loadContent(
        source: BookSource,
        book: BookInfoResult,
        chapter: BookChapterResult,
        policy: ContentLoadPolicy
    ) async throws -> ChapterContentResult {
        _ = policy
        callCount += 1
        if delay > .zero { try await Task.sleep(for: delay) }
        if shouldFail { throw TestContentError.failed }
        return ChapterContentResult(content: "network \(chapter.index)", chapterURL: chapter.url)
    }
}

private actor MemoryChapterCache: ChapterContentCache {
    private var entries: [ChapterCacheKey: ChapterContentCacheEntry]
    private let failsWrites: Bool

    init(entries: [ChapterCacheKey: ChapterContentCacheEntry] = [:], failsWrites: Bool = false) {
        self.entries = entries
        self.failsWrites = failsWrites
    }

    func content(for key: ChapterCacheKey) async -> ChapterContentCacheEntry? { entries[key] }
    func save(_ entry: ChapterContentCacheEntry) async throws {
        if failsWrites { throw TestContentError.failed }
        entries[entry.key] = entry
    }
    func remove(_ key: ChapterCacheKey) async { entries[key] = nil }
    func removeAll(for book: ChapterCacheBookKey) async {
        entries = entries.filter { $0.key.bookKey != book }
    }
    func clearExpired(before date: Date) async {
        entries = entries.filter { $0.value.cachedAt >= date }
    }
    func clearAll() async { entries.removeAll() }
}
