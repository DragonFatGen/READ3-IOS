import Combine
import Foundation
import LegadoCore
import SwiftUI

struct StoredBookSource: Codable, Equatable, Identifiable {
    var source: BookSource
    var isEnabled: Bool
    var groupName: String
    var sortOrder: Int
    var addedAt: Date
    var updatedAt: Date

    var id: String { source.bookSourceUrl }

    init(
        source: BookSource,
        isEnabled: Bool = true,
        groupName: String = "",
        sortOrder: Int,
        addedAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.source = source
        self.isEnabled = isEnabled
        self.groupName = groupName
        self.sortOrder = sortOrder
        self.addedAt = addedAt
        self.updatedAt = updatedAt
    }
}

enum BookSourceStoreError: LocalizedError, Equatable {
    case sourceNotFound
    case sourceIsReferenced(count: Int)
    case identityChangeBlocked
    case identityAlreadyExists

    var errorDescription: String? {
        switch self {
        case .sourceNotFound: "书源不存在"
        case let .sourceIsReferenced(count): "该书源仍被书架中的 \(count) 本书使用，请先移除相关书籍"
        case .identityChangeBlocked: "该书源已被书架引用，不能修改书源地址"
        case .identityAlreadyExists: "该书源地址已存在，不能生成重复书源"
        }
    }
}

@MainActor
final class BookSourceStore: ObservableObject {
    @Published private(set) var storedSources: [StoredBookSource] = []
    @Published var errorMessage: String?

    var allSources: [BookSource] { orderedStoredSources.map(\.source) }
    var enabledSources: [BookSource] {
        orderedStoredSources.filter(\.isEnabled).map(\.source)
    }
    // Compatibility for existing callers while management UI uses storedSources.
    var sources: [BookSource] { allSources }
    var groups: [String] {
        Array(Set(storedSources.map(\.groupName).filter { !$0.isEmpty })).sorted {
            $0.localizedStandardCompare($1) == .orderedAscending
        }
    }

    private let importer: BookSourceImporter
    private let defaults: UserDefaults
    private let storageKey: String
    private let now: () -> Date

    init(
        importer: BookSourceImporter = BookSourceImporter(),
        defaults: UserDefaults = .standard,
        storageKey: String = "book.sources.v1",
        now: @escaping () -> Date = Date.init
    ) {
        self.importer = importer
        self.defaults = defaults
        self.storageKey = storageKey
        self.now = now
        load()
    }

    var orderedStoredSources: [StoredBookSource] {
        storedSources.sorted {
            let lhsGroup = $0.groupName.isEmpty ? nil : $0.groupName
            let rhsGroup = $1.groupName.isEmpty ? nil : $1.groupName
            if lhsGroup != rhsGroup {
                if lhsGroup == nil { return false }
                if rhsGroup == nil { return true }
                return lhsGroup!.localizedStandardCompare(rhsGroup!) == .orderedAscending
            }
            if $0.sortOrder != $1.sortOrder { return $0.sortOrder < $1.sortOrder }
            if $0.addedAt != $1.addedAt { return $0.addedAt < $1.addedAt }
            return $0.id < $1.id
        }
    }

    func source(for identity: String) -> BookSource? {
        storedSources.first { $0.id == identity }?.source
    }

    func storedSource(for identity: String) -> StoredBookSource? {
        storedSources.first { $0.id == identity }
    }

    func importSources(from data: Data) {
        do {
            let result = try importer.importSources(from: data, mode: .lenient)
            result.successes.map(\.source).forEach(upsert)
            errorMessage = result.failures.isEmpty
                ? nil
                : "部分书源导入失败（\(result.failures.count) 个）"
            persist()
        } catch {
            errorMessage = UserFacingError.message(for: error, fallback: "无法导入书源")
        }
    }

    func upsert(_ source: BookSource) {
        let timestamp = now()
        if let index = storedSources.firstIndex(where: { $0.id == source.bookSourceUrl }) {
            storedSources[index].source = source
            storedSources[index].updatedAt = timestamp
        } else {
            storedSources.append(StoredBookSource(
                source: source,
                sortOrder: (storedSources.map(\.sortOrder).max() ?? -1) + 1,
                addedAt: timestamp,
                updatedAt: timestamp
            ))
        }
        persist()
    }

    func setEnabled(_ enabled: Bool, for identity: String) {
        update(identity) { $0.isEnabled = enabled }
    }

    func setEnabled(_ enabled: Bool, for identities: Set<String>) {
        guard !identities.isEmpty else { return }
        let timestamp = now()
        var changed = false
        for index in storedSources.indices where identities.contains(storedSources[index].id) {
            storedSources[index].isEnabled = enabled
            storedSources[index].updatedAt = timestamp
            changed = true
        }
        if changed { persist() }
    }

    func updateMetadata(identity: String, name: String, groupName: String, isEnabled: Bool) {
        update(identity) {
            $0.source.bookSourceName = name.trimmingCharacters(in: .whitespacesAndNewlines)
            $0.groupName = groupName.trimmingCharacters(in: .whitespacesAndNewlines)
            $0.isEnabled = isEnabled
        }
    }

    func move(fromOffsets: IndexSet, toOffset: Int, inGroup groupName: String) {
        var group = orderedStoredSources.filter { $0.groupName == groupName }
        group.move(fromOffsets: fromOffsets, toOffset: toOffset)
        for (order, value) in group.enumerated() {
            guard let index = storedSources.firstIndex(where: { $0.id == value.id }) else { continue }
            storedSources[index].sortOrder = order
            storedSources[index].updatedAt = now()
        }
        persist()
    }

    func remove(
        identity: String,
        library: LibraryRepository,
        allowingReferences: Bool = false
    ) throws {
        let count = library.referenceCount(forSourceIdentity: identity)
        guard allowingReferences || count == 0 else {
            throw BookSourceStoreError.sourceIsReferenced(count: count)
        }
        guard storedSources.contains(where: { $0.id == identity }) else {
            throw BookSourceStoreError.sourceNotFound
        }
        storedSources.removeAll { $0.id == identity }
        persist()
    }

    func remove(
        identities: Set<String>,
        library: LibraryRepository,
        allowingReferences: Bool = false
    ) throws {
        guard !identities.isEmpty else { return }
        if !allowingReferences {
            let count = identities.reduce(0) {
                $0 + library.referenceCount(forSourceIdentity: $1)
            }
            guard count == 0 else { throw BookSourceStoreError.sourceIsReferenced(count: count) }
        }
        storedSources.removeAll { identities.contains($0.id) }
        persist()
    }

    func referenceCount(for identities: Set<String>, library: LibraryRepository) -> Int {
        identities.reduce(0) { $0 + library.referenceCount(forSourceIdentity: $1) }
    }

    func editableJSON(for identity: String) throws -> String {
        guard let source = source(for: identity) else { throw BookSourceStoreError.sourceNotFound }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return String(decoding: try encoder.encode(source), as: UTF8.self)
    }

    func replaceFromJSON(_ json: String, identity: String, library: LibraryRepository) throws {
        guard let oldIndex = storedSources.firstIndex(where: { $0.id == identity }) else {
            throw BookSourceStoreError.sourceNotFound
        }
        let imported = try importer.importSource(from: Data(json.utf8)).source
        if imported.bookSourceUrl != identity,
           library.referenceCount(forSourceIdentity: identity) > 0 {
            throw BookSourceStoreError.identityChangeBlocked
        }
        if imported.bookSourceUrl != identity,
           storedSources.contains(where: { $0.id == imported.bookSourceUrl }) {
            throw BookSourceStoreError.identityAlreadyExists
        }
        var replacement = storedSources[oldIndex]
        replacement.source = imported
        replacement.updatedAt = now()
        storedSources[oldIndex] = replacement
        persist()
    }

    private func update(_ identity: String, mutation: (inout StoredBookSource) -> Void) {
        guard let index = storedSources.firstIndex(where: { $0.id == identity }) else { return }
        mutation(&storedSources[index])
        storedSources[index].updatedAt = now()
        persist()
    }

    private func load() {
        guard let data = defaults.data(forKey: storageKey) else { return }
        if let decoded = try? JSONDecoder().decode([StoredBookSource].self, from: data) {
            storedSources = decoded
            return
        }
        guard let legacy = try? JSONDecoder().decode([BookSource].self, from: data) else { return }
        let migrationDate = now()
        storedSources = legacy.enumerated().map { offset, source in
            StoredBookSource(
                source: source,
                isEnabled: true,
                groupName: "",
                sortOrder: offset,
                addedAt: migrationDate,
                updatedAt: migrationDate
            )
        }
        persist()
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(storedSources) else { return }
        defaults.set(data, forKey: storageKey)
    }
}
