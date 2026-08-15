import CryptoKit
import Foundation
import LegadoCore

struct ChapterCacheKey: Codable, Hashable, Sendable {
    let sourceIdentity: String
    let bookIdentity: String
    let chapterURL: String

    init(source: BookSource, book: BookInfoResult, chapter: BookChapterResult) {
        sourceIdentity = source.bookSourceUrl
        bookIdentity = book.bookURL
        chapterURL = chapter.url
    }

    var bookKey: ChapterCacheBookKey {
        ChapterCacheBookKey(sourceIdentity: sourceIdentity, bookIdentity: bookIdentity)
    }

    fileprivate var stableValue: String {
        [sourceIdentity, bookIdentity, chapterURL]
            .map { "\($0.utf8.count):\($0)" }
            .joined(separator: "|")
    }
}

struct ChapterCacheBookKey: Codable, Hashable, Sendable {
    let sourceIdentity: String
    let bookIdentity: String
}

struct ChapterContentCacheEntry: Codable, Equatable, Sendable {
    let key: ChapterCacheKey
    let chapterName: String
    let content: String
    let chapterURL: String
    let cachedAt: Date

    var result: ChapterContentResult {
        ChapterContentResult(content: content, chapterURL: chapterURL)
    }
}

protocol ChapterContentCache: Sendable {
    func content(for key: ChapterCacheKey) async -> ChapterContentCacheEntry?
    func save(_ entry: ChapterContentCacheEntry) async throws
    func remove(_ key: ChapterCacheKey) async
    func removeAll(for book: ChapterCacheBookKey) async
    func clearExpired(before date: Date) async
    func clearAll() async
}

struct ChapterCacheConfiguration: Sendable {
    static let production = ChapterCacheConfiguration(
        maximumDiskBytes: 100 * 1_024 * 1_024,
        targetDiskBytes: 80 * 1_024 * 1_024,
        memoryEntryLimit: 24
    )

    let maximumDiskBytes: Int64
    let targetDiskBytes: Int64
    let memoryEntryLimit: Int

    init(maximumDiskBytes: Int64, targetDiskBytes: Int64, memoryEntryLimit: Int) {
        self.maximumDiskBytes = max(maximumDiskBytes, 1)
        self.targetDiskBytes = min(max(targetDiskBytes, 0), self.maximumDiskBytes)
        self.memoryEntryLimit = max(memoryEntryLimit, 1)
    }
}

actor FileChapterContentCache: ChapterContentCache {
    private let directory: URL
    private let configuration: ChapterCacheConfiguration
    private let fileManager: FileManager
    private var memory: [ChapterCacheKey: ChapterContentCacheEntry] = [:]
    private var estimatedDiskBytes: Int64?

    init(
        directory: URL,
        configuration: ChapterCacheConfiguration = .production,
        fileManager: FileManager = .default
    ) {
        self.directory = directory
        self.configuration = configuration
        self.fileManager = fileManager
    }

    func content(for key: ChapterCacheKey) async -> ChapterContentCacheEntry? {
        if let entry = memory[key] { return entry }
        let url = fileURL(for: key)
        guard fileManager.fileExists(atPath: url.path) else { return nil }
        do {
            let data = try Data(contentsOf: url)
            let entry = try JSONDecoder().decode(ChapterContentCacheEntry.self, from: data)
            guard entry.key == key else { throw ChapterCacheError.invalidEntry }
            insertIntoMemory(entry)
            try? fileManager.setAttributes([.modificationDate: Date()], ofItemAtPath: url.path)
            return entry
        } catch {
            try? fileManager.removeItem(at: url)
            estimatedDiskBytes = nil
            return nil
        }
    }

    func save(_ entry: ChapterContentCacheEntry) async throws {
        try ensureDirectory()
        let data = try JSONEncoder().encode(entry)
        let url = fileURL(for: entry.key)
        let replacedBytes = fileSize(at: url)
        try data.write(to: url, options: .atomic)
        insertIntoMemory(entry)
        if let estimatedDiskBytes {
            self.estimatedDiskBytes = max(0, estimatedDiskBytes - replacedBytes) + Int64(data.count)
        } else {
            self.estimatedDiskBytes = try directorySize()
        }
        if (estimatedDiskBytes ?? 0) > configuration.maximumDiskBytes {
            try trimToTargetSize()
        }
    }

    func remove(_ key: ChapterCacheKey) async {
        memory.removeValue(forKey: key)
        let url = fileURL(for: key)
        let removedBytes = fileSize(at: url)
        try? fileManager.removeItem(at: url)
        if let estimatedDiskBytes { self.estimatedDiskBytes = max(0, estimatedDiskBytes - removedBytes) }
    }

    func removeAll(for book: ChapterCacheBookKey) async {
        memory = memory.filter { $0.key.bookKey != book }
        for url in cacheFiles() {
            guard let entry = decodeEntry(at: url) else {
                try? fileManager.removeItem(at: url)
                continue
            }
            if entry.key.bookKey == book { try? fileManager.removeItem(at: url) }
        }
        estimatedDiskBytes = nil
    }

    func clearExpired(before date: Date) async {
        memory = memory.filter { $0.value.cachedAt >= date }
        for url in cacheFiles() {
            guard let entry = decodeEntry(at: url) else {
                try? fileManager.removeItem(at: url)
                continue
            }
            if entry.cachedAt < date { try? fileManager.removeItem(at: url) }
        }
        estimatedDiskBytes = nil
    }

    func clearAll() async {
        memory.removeAll()
        try? fileManager.removeItem(at: directory)
        estimatedDiskBytes = 0
    }

    private func insertIntoMemory(_ entry: ChapterContentCacheEntry) {
        memory[entry.key] = entry
        guard memory.count > configuration.memoryEntryLimit,
              let oldest = memory.min(by: { $0.value.cachedAt < $1.value.cachedAt })?.key else { return }
        memory.removeValue(forKey: oldest)
    }

    private func ensureDirectory() throws {
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        var mutableDirectory = directory
        try? mutableDirectory.setResourceValues(values)
    }

    private func fileURL(for key: ChapterCacheKey) -> URL {
        let digest = SHA256.hash(data: Data(key.stableValue.utf8))
        let name = digest.map { String(format: "%02x", $0) }.joined()
        return directory.appendingPathComponent(name).appendingPathExtension("json")
    }

    private func cacheFiles() -> [URL] {
        (try? fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ))?.filter { $0.pathExtension == "json" } ?? []
    }

    private func decodeEntry(at url: URL) -> ChapterContentCacheEntry? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(ChapterContentCacheEntry.self, from: data)
    }

    private func fileSize(at url: URL) -> Int64 {
        let value = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize
        return Int64(value ?? 0)
    }

    private func directorySize() throws -> Int64 {
        cacheFiles().reduce(0) { $0 + fileSize(at: $1) }
    }

    private func trimToTargetSize() throws {
        var files = cacheFiles().map { url in
            let values = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
            return CacheFile(
                url: url,
                size: Int64(values?.fileSize ?? 0),
                date: values?.contentModificationDate ?? .distantPast
            )
        }.sorted { $0.date < $1.date }
        var size = files.reduce(0) { $0 + $1.size }
        while size > configuration.targetDiskBytes, !files.isEmpty {
            let oldest = files.removeFirst()
            try? fileManager.removeItem(at: oldest.url)
            size -= oldest.size
        }
        estimatedDiskBytes = max(size, 0)
        let remainingKeys = Set(cacheFiles().compactMap { decodeEntry(at: $0)?.key })
        memory = memory.filter { remainingKeys.contains($0.key) }
    }
}

private enum ChapterCacheError: Error { case invalidEntry }

private struct CacheFile {
    let url: URL
    let size: Int64
    let date: Date
}
