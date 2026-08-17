import Foundation

@MainActor
protocol ReaderSpeechSynthesizing: AnyObject {
    var eventHandler: ((ReaderSpeechEvent) -> Void)? { get set }
    var availableVoices: [ReaderSpeechVoice] { get }

    func speak(_ segment: ReaderSpeechSegment, rateMultiplier: Double, voiceIdentifier: String?)
    func pause()
    func resume()
    func stop()
}

@MainActor
protocol ReaderAudioSessionManaging: AnyObject {
    var eventHandler: ((ReaderAudioSessionEvent) -> Void)? { get set }
    func activate() throws
    func deactivate()
}

@MainActor
protocol ReaderRemoteCommandManaging: AnyObject {
    var commandHandler: ((ReaderRemoteCommand) -> Bool)? { get set }
    func updateNowPlaying(bookTitle: String, chapterTitle: String, isPlaying: Bool)
    func clearNowPlaying()
}

protocol ReaderSpeechSleeping: Sendable {
    func sleep(for duration: Duration) async throws
}

struct ContinuousReaderSpeechSleeper: ReaderSpeechSleeping {
    func sleep(for duration: Duration) async throws {
        try await Task.sleep(for: duration)
    }
}
