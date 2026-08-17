@preconcurrency import AVFoundation
import Foundation

@MainActor
final class AppleReaderSpeechSynthesizer: NSObject, ReaderSpeechSynthesizing {
    var eventHandler: ((ReaderSpeechEvent) -> Void)?

    var availableVoices: [ReaderSpeechVoice] {
        AVSpeechSynthesisVoice.speechVoices()
            .map { ReaderSpeechVoice(id: $0.identifier, name: $0.name, language: $0.language) }
            .sorted {
                if $0.isChinese != $1.isChinese { return $0.isChinese }
                if $0.language != $1.language { return $0.language < $1.language }
                return $0.name.localizedStandardCompare($1.name) == .orderedAscending
            }
    }

    private let synthesizer = AVSpeechSynthesizer()
    private var utteranceIDs: [ObjectIdentifier: UUID] = [:]

    override init() {
        super.init()
        synthesizer.delegate = self
    }

    func speak(_ segment: ReaderSpeechSegment, rateMultiplier: Double, voiceIdentifier: String?) {
        let utterance = AVSpeechUtterance(string: segment.text)
        utteranceIDs[ObjectIdentifier(utterance)] = segment.id
        utterance.rate = Self.appleRate(for: rateMultiplier)
        utterance.voice = voiceIdentifier.flatMap { AVSpeechSynthesisVoice(identifier: $0) }
            ?? AVSpeechSynthesisVoice(language: "zh-CN")
        synthesizer.speak(utterance)
    }

    func pause() {
        _ = synthesizer.pauseSpeaking(at: .word)
    }

    func resume() {
        _ = synthesizer.continueSpeaking()
    }

    func stop() {
        _ = synthesizer.stopSpeaking(at: .immediate)
    }

    static func appleRate(for multiplier: Double) -> Float {
        let value = min(max(multiplier, 0.5), 2)
        let base = Double(AVSpeechUtteranceDefaultSpeechRate)
        let minimum = Double(AVSpeechUtteranceMinimumSpeechRate)
        let maximum = Double(AVSpeechUtteranceMaximumSpeechRate)
        if value <= 1 {
            let fraction = (value - 0.5) / 0.5
            return Float(minimum + (base - minimum) * fraction)
        }
        return Float(base + (maximum - base) * (value - 1))
    }
}

extension AppleReaderSpeechSynthesizer: AVSpeechSynthesizerDelegate {
    nonisolated func speechSynthesizer(
        _ synthesizer: AVSpeechSynthesizer,
        didStart utterance: AVSpeechUtterance
    ) {
        emitOnMain(utterance, terminal: false) { id in .didStart(id) }
    }

    nonisolated func speechSynthesizer(
        _ synthesizer: AVSpeechSynthesizer,
        didFinish utterance: AVSpeechUtterance
    ) {
        emitOnMain(utterance, terminal: true) { id in .didFinish(id) }
    }

    nonisolated func speechSynthesizer(
        _ synthesizer: AVSpeechSynthesizer,
        didPause utterance: AVSpeechUtterance
    ) {
        emitOnMain(utterance, terminal: false) { id in .didPause(id) }
    }

    nonisolated func speechSynthesizer(
        _ synthesizer: AVSpeechSynthesizer,
        didContinue utterance: AVSpeechUtterance
    ) {
        emitOnMain(utterance, terminal: false) { id in .didContinue(id) }
    }

    nonisolated func speechSynthesizer(
        _ synthesizer: AVSpeechSynthesizer,
        didCancel utterance: AVSpeechUtterance
    ) {
        emitOnMain(utterance, terminal: true) { id in .didCancel(id) }
    }

    nonisolated private func emitOnMain(
        _ utterance: AVSpeechUtterance,
        terminal: Bool,
        event: @escaping @MainActor @Sendable (UUID) -> ReaderSpeechEvent
    ) {
        let key = ObjectIdentifier(utterance)
        Task { @MainActor [weak self] in
            guard let self, let id = self.utteranceIDs[key] else { return }
            if terminal { self.utteranceIDs[key] = nil }
            self.eventHandler?(event(id))
        }
    }
}
