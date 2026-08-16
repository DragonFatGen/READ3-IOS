import Foundation
import LegadoCore
import XCTest
@testable import LegadoIOS

@MainActor
final class LibraryAutoUpdateCoordinatorTests: XCTestCase {
    func testFirstActiveRunsSecondInsideIntervalSkipsAndLaterActiveRuns() async {
        let fixture = makeFixture(bookCount: 2)
        let start = Date(timeIntervalSince1970: 100_000)
        await fixture.coordinator.checkIfNeeded(now: start)
        var callCount = await fixture.checker.callCount
        XCTAssertEqual(callCount, 2)
        XCTAssertEqual(fixture.settings.lastAutomaticCheckAt, start)

        await fixture.coordinator.checkIfNeeded(now: start.addingTimeInterval(10 * 60))
        callCount = await fixture.checker.callCount
        XCTAssertEqual(callCount, 2)
        await fixture.coordinator.checkIfNeeded(now: start.addingTimeInterval(6 * 60 * 60))
        callCount = await fixture.checker.callCount
        XCTAssertEqual(callCount, 4)
    }

    func testDisabledAndEmptyLibraryDoNoNetworkWork() async {
        let disabled = makeFixture(bookCount: 1)
        disabled.settings.setAutomaticCheckEnabled(false)
        await disabled.coordinator.checkIfNeeded(now: Date())
        var callCount = await disabled.checker.callCount
        XCTAssertEqual(callCount, 0)

        let empty = makeFixture(bookCount: 0)
        await empty.coordinator.checkIfNeeded(now: Date())
        callCount = await empty.checker.callCount
        XCTAssertEqual(callCount, 0)
        XCTAssertNil(empty.settings.lastAutomaticCheckAt)
    }

    func testRepeatedActiveAndManualRefreshDoNotDuplicateBatch() async {
        let fixture = makeFixture(bookCount: 3, delay: .milliseconds(40))
        fixture.coordinator.applicationDidBecomeActive(now: Date(timeIntervalSince1970: 1))
        fixture.coordinator.applicationDidBecomeActive(now: Date(timeIntervalSince1970: 1))
        await wait { !fixture.coordinator.isRunning }
        var callCount = await fixture.checker.callCount
        XCTAssertEqual(callCount, 3)

        fixture.settings.lastAutomaticCheckAt = nil
        let manual = Task { await fixture.viewModel.refreshAll() }
        await wait { fixture.viewModel.isRefreshingAll }
        await fixture.coordinator.checkIfNeeded(now: Date(timeIntervalSince1970: 2))
        _ = await manual.value
        callCount = await fixture.checker.callCount
        XCTAssertEqual(callCount, 6)
    }

    func testNotificationUsesNewDeltaWhileBadgeKeepsAccumulatedCount() async {
        let fixture = makeFixture(bookCount: 1, newChapterCount: 3)
        let bookID = fixture.repository.books[0].id
        fixture.repository.applyUpdateCheck(
            bookID: bookID,
            result: BookUpdateResult(
                checkedAt: Date(timeIntervalSince1970: 1), chapterCount: 105,
                latestChapterName: "第 105 章", latestChapterURL: "chapter-105",
                newChapterCount: 5
            )
        )
        await fixture.settings.setNotificationEnabled(true, notifier: fixture.notifier)
        await fixture.coordinator.checkIfNeeded(now: Date(timeIntervalSince1970: 2))

        XCTAssertEqual(fixture.repository.books[0].updateCount, 8)
        XCTAssertEqual(fixture.notifier.notifications.count, 1)
        XCTAssertEqual(fixture.notifier.notifications[0].first?.newChapterCount, 3)
    }

    func testNotificationDisabledAndZeroDeltaDoNotNotify() async {
        let disabled = makeFixture(bookCount: 1, newChapterCount: 3)
        await disabled.coordinator.checkIfNeeded(now: Date())
        XCTAssertTrue(disabled.notifier.notifications.isEmpty)

        let zero = makeFixture(bookCount: 1, newChapterCount: 0)
        await zero.settings.setNotificationEnabled(true, notifier: zero.notifier)
        await zero.coordinator.checkIfNeeded(now: Date())
        XCTAssertTrue(zero.notifier.notifications.isEmpty)
    }

    func testImmediateForegroundCancellationDoesNotSuppressNextAutomaticCheck() async {
        let fixture = makeFixture(bookCount: 3, delay: .milliseconds(80))
        fixture.coordinator.applicationDidBecomeActive(now: Date(timeIntervalSince1970: 10))
        await wait { fixture.viewModel.isRefreshingAll }
        fixture.coordinator.applicationDidLeaveActiveState()
        await wait { !fixture.viewModel.isRefreshingAll }
        XCTAssertNil(fixture.settings.lastAutomaticCheckAt)

        await fixture.coordinator.checkIfNeeded(now: Date(timeIntervalSince1970: 11))
        let callCount = await fixture.checker.callCount
        XCTAssertGreaterThanOrEqual(callCount, 3)
    }

    private func makeFixture(
        bookCount: Int,
        newChapterCount: Int = 0,
        delay: Duration = .zero
    ) -> Fixture {
        let suite = "LibraryAutoUpdateCoordinatorTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let repository = LibraryRepository(defaults: defaults, storageKey: "library")
        let sourceStore = BookSourceStore(defaults: defaults, storageKey: "sources")
        sourceStore.upsert(testSource())
        for index in 0..<bookCount {
            repository.add(source: testSource(), bookInfo: autoBookInfo(index: index))
        }
        let checker = AutoUpdateChecker(newChapterCount: newChapterCount, delay: delay)
        let viewModel = LibraryViewModel(
            repository: repository, sourceStore: sourceStore, checker: checker
        )
        let settings = LibraryUpdateSettingsStore(defaults: defaults, keyPrefix: "settings")
        let notifier = FakeLibraryUpdateNotifier(status: .authorized)
        return Fixture(
            repository: repository,
            viewModel: viewModel,
            settings: settings,
            notifier: notifier,
            checker: checker,
            coordinator: LibraryAutoUpdateCoordinator(
                repository: repository, libraryViewModel: viewModel,
                settingsStore: settings, notifier: notifier
            )
        )
    }

    private func wait(attempts: Int = 100, until condition: @escaping () -> Bool) async {
        for _ in 0..<attempts {
            if condition() { return }
            try? await Task.sleep(for: .milliseconds(2))
        }
        XCTFail("Timed out waiting for automatic update state")
    }
}

@MainActor
private struct Fixture {
    let repository: LibraryRepository
    let viewModel: LibraryViewModel
    let settings: LibraryUpdateSettingsStore
    let notifier: FakeLibraryUpdateNotifier
    let checker: AutoUpdateChecker
    let coordinator: LibraryAutoUpdateCoordinator
}

private actor AutoUpdateChecker: BookUpdateChecking {
    private let newChapterCount: Int
    private let delay: Duration
    private(set) var callCount = 0

    init(newChapterCount: Int, delay: Duration) {
        self.newChapterCount = newChapterCount
        self.delay = delay
    }

    func checkUpdate(for book: LibraryBook, source: BookSource) async throws -> BookUpdateResult {
        callCount += 1
        if delay > .zero { try await Task.sleep(for: delay) }
        let oldCount = book.lastKnownChapterCount ?? 100
        let count = oldCount + newChapterCount
        return BookUpdateResult(
            checkedAt: Date(timeIntervalSince1970: Double(count)), chapterCount: count,
            latestChapterName: "第 \(count) 章", latestChapterURL: "chapter-\(count)",
            newChapterCount: newChapterCount
        )
    }
}

private func autoBookInfo(index: Int) -> BookInfoResult {
    BookInfoResult(
        name: "自动更新书 \(index)", author: "作者",
        bookURL: "https://source.example/auto/\(index)",
        tocURL: "https://source.example/auto/\(index)/toc",
        sourceURL: testSource().bookSourceUrl, sourceName: testSource().bookSourceName,
        sourceType: 0, sourceOrder: 0
    )
}
