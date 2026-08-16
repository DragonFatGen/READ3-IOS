import Foundation
import LegadoCore
import XCTest
@testable import LegadoIOS

@MainActor
final class BookSourceStoreTests: XCTestCase {
    func testLegacyMigrationPreservesOrderIdentityAndEnablesAll() throws {
        let fixture = makeDefaults()
        let sources = [source("https://one.example", "一"), source("https://two.example", "二")]
        fixture.defaults.set(try JSONEncoder().encode(sources), forKey: fixture.key)

        let store = BookSourceStore(defaults: fixture.defaults, storageKey: fixture.key)

        XCTAssertEqual(store.allSources.map(\.bookSourceUrl), sources.map(\.bookSourceUrl))
        XCTAssertEqual(store.enabledSources.count, 2)
        XCTAssertEqual(store.storedSources.map(\.sortOrder), [0, 1])
        XCTAssertNoThrow(try JSONDecoder().decode(
            [StoredBookSource].self,
            from: XCTUnwrap(fixture.defaults.data(forKey: fixture.key))
        ))
    }

    func testImportDefaultsEnabledAndDuplicatePreservesMetadata() throws {
        let fixture = makeDefaults()
        let clock = MutableClock(Date(timeIntervalSince1970: 1))
        let store = BookSourceStore(
            defaults: fixture.defaults, storageKey: fixture.key, now: { clock.value }
        )
        store.importSources(from: try JSONEncoder().encode(source("https://one.example", "旧名称")))
        store.setEnabled(false, for: "https://one.example")
        store.updateMetadata(
            identity: "https://one.example", name: "旧名称", groupName: "小说", isEnabled: false
        )
        clock.value = Date(timeIntervalSince1970: 2)
        store.importSources(from: try JSONEncoder().encode(source("https://one.example", "新名称")))

        XCTAssertEqual(store.storedSources.count, 1)
        let value = try XCTUnwrap(store.storedSource(for: "https://one.example"))
        XCTAssertEqual(value.source.bookSourceName, "新名称")
        XCTAssertFalse(value.isEnabled)
        XCTAssertEqual(value.groupName, "小说")
        XCTAssertEqual(value.addedAt, Date(timeIntervalSince1970: 1))
        XCTAssertEqual(value.updatedAt, Date(timeIntervalSince1970: 2))
        XCTAssertTrue(store.enabledSources.isEmpty)
        XCTAssertEqual(store.allSources.count, 1)
    }

    func testMetadataMoveAndPersistence() throws {
        let fixture = makeDefaults()
        let first = BookSourceStore(defaults: fixture.defaults, storageKey: fixture.key)
        first.upsert(source("https://one.example", "一"))
        first.upsert(source("https://two.example", "二"))
        first.updateMetadata(identity: "https://one.example", name: "一", groupName: "组", isEnabled: true)
        first.updateMetadata(identity: "https://two.example", name: "二", groupName: "组", isEnabled: true)
        first.move(fromOffsets: IndexSet(integer: 1), toOffset: 0, inGroup: "组")

        let restored = BookSourceStore(defaults: fixture.defaults, storageKey: fixture.key)
        XCTAssertEqual(restored.groups, ["组"])
        XCTAssertEqual(restored.orderedStoredSources.map(\.id), ["https://two.example", "https://one.example"])
    }

    func testDeleteProtectionAndIdentityEditProtection() throws {
        let fixture = makeDefaults()
        let store = BookSourceStore(defaults: fixture.defaults, storageKey: fixture.key)
        store.upsert(testSource())
        let libraryFixture = makeDefaults()
        let library = LibraryRepository(defaults: libraryFixture.defaults, storageKey: libraryFixture.key)
        library.add(source: testSource(), bookInfo: testBookInfo())

        XCTAssertThrowsError(try store.remove(identity: testSource().bookSourceUrl, library: library))
        let changed = source("https://changed.example", "改变")
        let json = String(decoding: try JSONEncoder().encode(changed), as: UTF8.self)
        XCTAssertThrowsError(try store.replaceFromJSON(
            json, identity: testSource().bookSourceUrl, library: library
        ))
        XCTAssertEqual(store.allSources.first?.bookSourceUrl, testSource().bookSourceUrl)

        library.remove(bookID: try XCTUnwrap(library.books.first?.id))
        XCTAssertNoThrow(try store.remove(identity: testSource().bookSourceUrl, library: library))
    }

    func testInvalidJSONDoesNotReplaceSource() {
        let fixture = makeDefaults()
        let store = BookSourceStore(defaults: fixture.defaults, storageKey: fixture.key)
        store.upsert(testSource())
        let libraryFixture = makeDefaults()
        let library = LibraryRepository(defaults: libraryFixture.defaults, storageKey: libraryFixture.key)
        XCTAssertThrowsError(try store.replaceFromJSON(
            "not-json", identity: testSource().bookSourceUrl, library: library
        ))
        XCTAssertEqual(store.allSources.first, testSource())
    }

    func testDisabledSourceRemainsAvailableToExistingLibraryBook() throws {
        let fixture = makeDefaults()
        let store = BookSourceStore(defaults: fixture.defaults, storageKey: fixture.key)
        store.upsert(testSource())
        store.setEnabled(false, for: testSource().bookSourceUrl)
        let book = LibraryBook(source: testSource(), bookInfo: testBookInfo())

        XCTAssertTrue(store.enabledSources.isEmpty)
        XCTAssertEqual(store.source(for: book.source.bookSourceUrl), book.source)
    }

    private func source(_ identity: String, _ name: String) -> BookSource {
        BookSource(bookSourceUrl: identity, bookSourceName: name, searchUrl: identity + "/search")
    }

    private func makeDefaults() -> (defaults: UserDefaults, key: String) {
        let suite = "BookSourceStoreTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return (defaults, "values")
    }
}

private final class MutableClock {
    var value: Date
    init(_ value: Date) { self.value = value }
}
