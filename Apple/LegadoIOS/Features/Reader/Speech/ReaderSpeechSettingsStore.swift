import Combine
import Foundation

@MainActor
final class ReaderSpeechSettingsStore: ObservableObject {
    @Published private(set) var settings: ReaderSpeechSettings

    private let defaults: UserDefaults
    private let keyPrefix: String

    init(defaults: UserDefaults = .standard, keyPrefix: String = "reader.speech.settings") {
        self.defaults = defaults
        self.keyPrefix = keyPrefix
        let fallback = ReaderSpeechSettings.default
        settings = ReaderSpeechSettings(
            rate: defaults.object(forKey: "\(keyPrefix).rate") == nil
                ? fallback.rate : defaults.double(forKey: "\(keyPrefix).rate"),
            voiceIdentifier: defaults.string(forKey: "\(keyPrefix).voiceIdentifier"),
            continuousReading: defaults.object(forKey: "\(keyPrefix).continuousReading") == nil
                ? fallback.continuousReading
                : defaults.bool(forKey: "\(keyPrefix).continuousReading"),
            sleepTimerOption: .off
        ).validated()
    }

    func selectRate(_ rate: Double) {
        settings.rate = rate
        settings = settings.validated()
        persist()
    }

    func selectVoice(identifier: String?) {
        settings.voiceIdentifier = identifier
        persist()
    }

    func selectContinuousReading(_ enabled: Bool) {
        settings.continuousReading = enabled
        persist()
    }

    func validateVoice(against voices: [ReaderSpeechVoice]) {
        let validated = settings.validated(availableVoiceIdentifiers: Set(voices.map(\.id)))
        guard validated != settings else { return }
        settings = validated
        persist()
    }

    private func persist() {
        defaults.set(settings.rate, forKey: "\(keyPrefix).rate")
        if let voiceIdentifier = settings.voiceIdentifier {
            defaults.set(voiceIdentifier, forKey: "\(keyPrefix).voiceIdentifier")
        } else {
            defaults.removeObject(forKey: "\(keyPrefix).voiceIdentifier")
        }
        defaults.set(settings.continuousReading, forKey: "\(keyPrefix).continuousReading")
    }
}
