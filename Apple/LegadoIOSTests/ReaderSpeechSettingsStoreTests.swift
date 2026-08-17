@preconcurrency import AVFoundation
import XCTest
@testable import LegadoIOS

@MainActor
final class ReaderSpeechSettingsStoreTests: XCTestCase {
    func testLegacyMissingSettingsUseSafeDefaults() {
        let defaults = makeDefaults()
        let store = ReaderSpeechSettingsStore(defaults: defaults, keyPrefix: "tts")
        XCTAssertEqual(store.settings, .default)
    }

    func testRatePersists() {
        let defaults = makeDefaults()
        ReaderSpeechSettingsStore(defaults: defaults, keyPrefix: "tts").selectRate(1.5)
        XCTAssertEqual(
            ReaderSpeechSettingsStore(defaults: defaults, keyPrefix: "tts").settings.rate,
            1.5
        )
    }

    func testUnsupportedRateUsesNearestSupportedValue() {
        let store = ReaderSpeechSettingsStore(defaults: makeDefaults(), keyPrefix: "tts")
        store.selectRate(1.37)
        XCTAssertEqual(store.settings.rate, 1.5)
    }

    func testVoiceAndContinuousReadingPersist() {
        let defaults = makeDefaults()
        let first = ReaderSpeechSettingsStore(defaults: defaults, keyPrefix: "tts")
        first.selectVoice(identifier: "voice.zh")
        first.selectContinuousReading(false)
        let restored = ReaderSpeechSettingsStore(defaults: defaults, keyPrefix: "tts")
        XCTAssertEqual(restored.settings.voiceIdentifier, "voice.zh")
        XCTAssertFalse(restored.settings.continuousReading)
    }

    func testInvalidSavedVoiceFallsBackToSystemDefault() {
        let defaults = makeDefaults()
        let store = ReaderSpeechSettingsStore(defaults: defaults, keyPrefix: "tts")
        store.selectVoice(identifier: "removed.voice")
        store.validateVoice(against: [ReaderSpeechVoice(id: "available", name: "中文", language: "zh-CN")])
        XCTAssertNil(store.settings.voiceIdentifier)
    }

    func testSleepTimerIsNotRestored() {
        let defaults = makeDefaults()
        defaults.set(ReaderSleepTimerOption.sixtyMinutes.rawValue, forKey: "tts.sleepTimerOption")
        XCTAssertEqual(
            ReaderSpeechSettingsStore(defaults: defaults, keyPrefix: "tts").settings.sleepTimerOption,
            .off
        )
    }

    func testUserMultiplierMapsInsideAppleRateRange() {
        XCTAssertEqual(
            AppleReaderSpeechSynthesizer.appleRate(for: 1),
            AVSpeechUtteranceDefaultSpeechRate,
            accuracy: 0.0001
        )
        XCTAssertGreaterThan(
            AppleReaderSpeechSynthesizer.appleRate(for: 2),
            AVSpeechUtteranceDefaultSpeechRate
        )
        XCTAssertLessThanOrEqual(
            AppleReaderSpeechSynthesizer.appleRate(for: 2),
            AVSpeechUtteranceMaximumSpeechRate
        )
    }

    private func makeDefaults() -> UserDefaults {
        let suite = "ReaderSpeechSettingsTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }
}
