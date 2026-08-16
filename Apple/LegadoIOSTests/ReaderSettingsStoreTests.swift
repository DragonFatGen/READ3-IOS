import XCTest
@testable import LegadoIOS

@MainActor
final class ReaderSettingsStoreTests: XCTestCase {
    func testDefaults() {
        let defaults = isolatedDefaults()
        let store = ReaderSettingsStore(defaults: defaults, keyPrefix: "settings")
        XCTAssertEqual(store.settings, .default)
        XCTAssertEqual(store.settings.layoutMode, .scroll)
        XCTAssertEqual(store.settings.pageTurnStyle, .cover)
    }

    func testPersistsAcrossStoreInstances() {
        let defaults = isolatedDefaults()
        let first = ReaderSettingsStore(defaults: defaults, keyPrefix: "settings")
        first.adjustFontSize(by: 3)
        first.adjustLineSpacing(by: 2)
        first.adjustHorizontalPadding(by: 4)
        first.selectTheme(.sepia)
        first.selectLayoutMode(.paged)
        first.selectPageTurnStyle(.none)

        let restored = ReaderSettingsStore(defaults: defaults, keyPrefix: "settings")
        XCTAssertEqual(restored.settings, first.settings)
        XCTAssertEqual(restored.settings.layoutMode, .paged)
        XCTAssertEqual(restored.settings.pageTurnStyle, .none)
    }

    func testLegacySettingsWithoutPageTurnStyleUsesCoverDefault() {
        let defaults = isolatedDefaults()
        defaults.set(ReaderLayoutMode.paged.rawValue, forKey: "settings.layoutMode")

        let store = ReaderSettingsStore(defaults: defaults, keyPrefix: "settings")

        XCTAssertEqual(store.settings.pageTurnStyle, .cover)
    }

    func testRangesAreClamped() {
        let defaults = isolatedDefaults()
        defaults.set(200.0, forKey: "settings.fontSize")
        defaults.set(-10.0, forKey: "settings.lineSpacing")
        defaults.set(100.0, forKey: "settings.horizontalPadding")

        let store = ReaderSettingsStore(defaults: defaults, keyPrefix: "settings")
        XCTAssertEqual(store.settings.fontSize, ReaderSettings.fontSizeRange.upperBound)
        XCTAssertEqual(store.settings.lineSpacing, ReaderSettings.lineSpacingRange.lowerBound)
        XCTAssertEqual(store.settings.horizontalPadding, ReaderSettings.horizontalPaddingRange.upperBound)
    }

    private func isolatedDefaults() -> UserDefaults {
        let suite = "ReaderSettingsStoreTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }
}
