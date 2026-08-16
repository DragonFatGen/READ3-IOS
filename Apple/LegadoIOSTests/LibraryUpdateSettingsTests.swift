import Foundation
import XCTest
@testable import LegadoIOS

@MainActor
final class LibraryUpdateSettingsTests: XCTestCase {
    func testDefaultsAndPersistenceMigration() {
        let fixture = defaultsFixture()
        let store = LibraryUpdateSettingsStore(defaults: fixture.defaults, keyPrefix: fixture.prefix)
        XCTAssertEqual(store.settings, .default)
        XCTAssertNil(store.lastAutomaticCheckAt)
        let untouchedNotifier = FakeLibraryUpdateNotifier(status: .notDetermined)
        XCTAssertEqual(untouchedNotifier.requestCount, 0)

        store.setAutomaticCheckEnabled(false)
        store.setInterval(.daily)
        store.lastAutomaticCheckAt = Date(timeIntervalSince1970: 123)
        let restored = LibraryUpdateSettingsStore(defaults: fixture.defaults, keyPrefix: fixture.prefix)
        XCTAssertFalse(restored.settings.automaticCheckEnabled)
        XCTAssertEqual(restored.settings.automaticCheckInterval, .daily)
        XCTAssertEqual(restored.lastAutomaticCheckAt, Date(timeIntervalSince1970: 123))
    }

    func testAutoUpdatePolicyIntervalsAndFutureDateDefense() {
        let policy = LibraryAutoUpdatePolicy()
        let now = Date(timeIntervalSince1970: 100_000)
        var settings = LibraryUpdateSettings.default
        settings.automaticCheckEnabled = false
        XCTAssertFalse(policy.shouldCheck(now: now, lastAutomaticCheckAt: nil, settings: settings))

        settings.automaticCheckEnabled = true
        XCTAssertTrue(policy.shouldCheck(now: now, lastAutomaticCheckAt: nil, settings: settings))
        settings.automaticCheckInterval = .everyHour
        XCTAssertFalse(policy.shouldCheck(
            now: now, lastAutomaticCheckAt: now.addingTimeInterval(-59 * 60), settings: settings
        ))
        XCTAssertTrue(policy.shouldCheck(
            now: now, lastAutomaticCheckAt: now.addingTimeInterval(-60 * 60), settings: settings
        ))
        settings.automaticCheckInterval = .every6Hours
        XCTAssertTrue(policy.shouldCheck(
            now: now, lastAutomaticCheckAt: now.addingTimeInterval(-6 * 60 * 60), settings: settings
        ))
        settings.automaticCheckInterval = .daily
        XCTAssertFalse(policy.shouldCheck(
            now: now, lastAutomaticCheckAt: now.addingTimeInterval(-23 * 60 * 60), settings: settings
        ))
        XCTAssertTrue(policy.shouldCheck(
            now: now, lastAutomaticCheckAt: now.addingTimeInterval(-24 * 60 * 60), settings: settings
        ))
        XCTAssertFalse(policy.shouldCheck(
            now: now, lastAutomaticCheckAt: now.addingTimeInterval(60), settings: settings
        ))
    }

    func testPermissionDeniedKeepsNotificationsDisabledAndExternalDisableIsSynchronized() async {
        let fixture = defaultsFixture()
        let store = LibraryUpdateSettingsStore(defaults: fixture.defaults, keyPrefix: fixture.prefix)
        let denied = FakeLibraryUpdateNotifier(status: .notDetermined, grantsRequest: false)
        await store.setNotificationEnabled(true, notifier: denied)
        XCTAssertFalse(store.settings.notificationEnabled)
        XCTAssertEqual(store.notificationPermissionMessage, "通知权限未开启")
        XCTAssertEqual(denied.requestCount, 1)

        let authorized = FakeLibraryUpdateNotifier(status: .authorized)
        await store.setNotificationEnabled(true, notifier: authorized)
        XCTAssertTrue(store.settings.notificationEnabled)
        authorized.status = .denied
        await store.synchronizeNotificationAuthorization(using: authorized)
        XCTAssertFalse(store.settings.notificationEnabled)
    }

    private func defaultsFixture() -> (defaults: UserDefaults, prefix: String) {
        let suite = "LibraryUpdateSettingsTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return (defaults, "settings")
    }
}

@MainActor
final class FakeLibraryUpdateNotifier: LibraryUpdateNotifying {
    var status: LibraryNotificationAuthorizationStatus
    var grantsRequest: Bool
    private(set) var requestCount = 0
    private(set) var notifications: [[LibraryBookUpdateNotification]] = []

    init(status: LibraryNotificationAuthorizationStatus, grantsRequest: Bool = true) {
        self.status = status
        self.grantsRequest = grantsRequest
    }

    func authorizationStatus() async -> LibraryNotificationAuthorizationStatus { status }
    func requestAuthorization() async -> Bool {
        requestCount += 1
        if grantsRequest { status = .authorized }
        return grantsRequest
    }
    func notify(updates: [LibraryBookUpdateNotification]) async { notifications.append(updates) }
}
