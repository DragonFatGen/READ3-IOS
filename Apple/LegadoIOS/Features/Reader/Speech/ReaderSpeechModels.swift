import Foundation

enum ReaderSpeechState: Equatable {
    case idle
    case preparing
    case speaking
    case paused
}

struct ReaderSpeechSegment: Identifiable, Equatable, Sendable {
    let id: UUID
    let text: String
    let startUTF16Offset: Int
    let endUTF16Offset: Int

    init(
        id: UUID = UUID(),
        text: String,
        startUTF16Offset: Int,
        endUTF16Offset: Int
    ) {
        self.id = id
        self.text = text
        self.startUTF16Offset = startUTF16Offset
        self.endUTF16Offset = endUTF16Offset
    }

    func contains(utf16Offset: Int) -> Bool {
        startUTF16Offset <= utf16Offset && utf16Offset < endUTF16Offset
    }
}

struct ReaderSpeechVoice: Identifiable, Equatable, Sendable {
    let id: String
    let name: String
    let language: String

    var isChinese: Bool { language.lowercased().hasPrefix("zh") }
}

enum ReaderSleepTimerOption: String, CaseIterable, Equatable, Sendable {
    case off
    case fifteenMinutes
    case thirtyMinutes
    case sixtyMinutes
    case endOfChapter

    var title: String {
        switch self {
        case .off: "关闭"
        case .fifteenMinutes: "15 分钟"
        case .thirtyMinutes: "30 分钟"
        case .sixtyMinutes: "60 分钟"
        case .endOfChapter: "本章结束"
        }
    }

    var duration: Duration? {
        switch self {
        case .off, .endOfChapter: nil
        case .fifteenMinutes: .seconds(15 * 60)
        case .thirtyMinutes: .seconds(30 * 60)
        case .sixtyMinutes: .seconds(60 * 60)
        }
    }
}

struct ReaderSpeechSettings: Equatable, Sendable {
    static let supportedRates: [Double] = [0.8, 1.0, 1.2, 1.5, 2.0]

    var rate: Double
    var voiceIdentifier: String?
    var continuousReading: Bool
    // This is session-only. ReaderSpeechSettingsStore intentionally does not persist it.
    var sleepTimerOption: ReaderSleepTimerOption

    static let `default` = ReaderSpeechSettings(
        rate: 1,
        voiceIdentifier: nil,
        continuousReading: true,
        sleepTimerOption: .off
    )

    func validated(availableVoiceIdentifiers: Set<String>? = nil) -> ReaderSpeechSettings {
        let nearestRate = Self.supportedRates.min { abs($0 - rate) < abs($1 - rate) } ?? 1
        var voice = voiceIdentifier
        if let identifier = voice, let availableVoiceIdentifiers,
           !availableVoiceIdentifiers.contains(identifier) {
            voice = nil
        }
        return ReaderSpeechSettings(
            rate: nearestRate,
            voiceIdentifier: voice,
            continuousReading: continuousReading,
            sleepTimerOption: sleepTimerOption
        )
    }
}

enum ReaderSpeechEvent: Equatable, Sendable {
    case didStart(UUID)
    case didFinish(UUID)
    case didPause(UUID)
    case didContinue(UUID)
    case didCancel(UUID)
}

enum ReaderAudioSessionEvent: Equatable, Sendable {
    case interruptionBegan
    case headphonesRemoved
}

enum ReaderRemoteCommand: Equatable, Sendable {
    case play
    case pause
    case togglePlayPause
    case next
    case previous
}
