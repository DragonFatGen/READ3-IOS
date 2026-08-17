import Combine
import Foundation

@MainActor
final class ReaderSpeechController: ObservableObject {
    @Published private(set) var state: ReaderSpeechState = .idle
    @Published private(set) var speechErrorMessage: String?
    @Published private(set) var currentSegmentIndex: Int?
    @Published private(set) var sleepTimerOption: ReaderSleepTimerOption = .off

    let settingsStore: ReaderSpeechSettingsStore

    var availableVoices: [ReaderSpeechVoice] { synthesizer.availableVoices }
    var currentRateText: String { String(format: "%.1fx", settingsStore.settings.rate) }

    private let synthesizer: any ReaderSpeechSynthesizing
    private let audioSession: any ReaderAudioSessionManaging
    private let remoteCommands: any ReaderRemoteCommandManaging
    private let segmenter: ReaderSpeechSegmenter
    private let sleeper: any ReaderSpeechSleeping
    private var segments: [ReaderSpeechSegment] = []
    private var activeReader: ReaderViewModel?
    private weak var visibleReader: ReaderViewModel?
    private var activeBookID: String?
    private var sleepTask: Task<Void, Never>?
    private var resumeAfterNavigation = false
    private var pausedWithoutUtterance = false
    private var ignoredCancellationIDs: Set<UUID> = []

    init(
        synthesizer: any ReaderSpeechSynthesizing,
        audioSession: any ReaderAudioSessionManaging,
        remoteCommands: any ReaderRemoteCommandManaging,
        settingsStore: ReaderSpeechSettingsStore,
        segmenter: ReaderSpeechSegmenter = ReaderSpeechSegmenter(),
        sleeper: any ReaderSpeechSleeping = ContinuousReaderSpeechSleeper()
    ) {
        self.synthesizer = synthesizer
        self.audioSession = audioSession
        self.remoteCommands = remoteCommands
        self.settingsStore = settingsStore
        self.segmenter = segmenter
        self.sleeper = sleeper

        synthesizer.eventHandler = { [weak self] event in self?.handle(event) }
        audioSession.eventHandler = { [weak self] event in self?.handle(event) }
        remoteCommands.commandHandler = { [weak self] command in
            self?.handle(command) ?? false
        }
        settingsStore.validateVoice(against: synthesizer.availableVoices)
    }

    deinit { sleepTask?.cancel() }

    func connect(_ reader: ReaderViewModel) {
        visibleReader = reader
        reader.attachSpeechController(self)
        guard state != .idle, activeBookID == reader.libraryBookIdentity else { return }
        let chapterIndex = activeReader?.currentChapterIndex ?? reader.currentChapterIndex
        let progress = currentNormalizedProgress
        activeReader = reader
        reader.synchronizeToSpeech(
            chapterIndex: chapterIndex,
            normalizedProgress: progress
        )
    }

    func readerDidDisappear(_ reader: ReaderViewModel) {
        if visibleReader === reader { visibleReader = nil }
        if activeReader === reader, state != .idle {
            reader.saveProgressNow()
        } else if state != .idle, activeBookID == reader.libraryBookIdentity {
            // A newly opened Reader for the same book owns the live position now.
            reader.cancel(persistProgress: false)
        } else {
            reader.cancel()
        }
    }

    func isSession(for reader: ReaderViewModel) -> Bool {
        state != .idle && activeBookID == reader.libraryBookIdentity
    }

    func togglePlayback(from reader: ReaderViewModel) {
        if !isSession(for: reader) {
            start(from: reader)
            return
        }
        switch state {
        case .speaking: pause()
        case .paused:
            if pausedWithoutUtterance {
                pausedWithoutUtterance = false
                speakCurrentSegment()
            } else {
                synthesizer.resume()
                state = .speaking
                updateNowPlaying(isPlaying: true)
            }
        case .idle: start(from: reader)
        case .preparing: pause()
        }
    }

    func start(from reader: ReaderViewModel) {
        if state != .idle { stop(clearError: true) }
        activeReader = reader
        activeBookID = reader.libraryBookIdentity
        speechErrorMessage = nil
        guard prepareSegments(from: reader, progress: reader.currentNormalizedProgress) else {
            fail("当前没有可朗读内容")
            return
        }
        do {
            try audioSession.activate()
        } catch {
            fail("无法启动系统语音")
            return
        }
        speakCurrentSegment()
    }

    func pause() {
        guard state == .speaking || state == .preparing else { return }
        synthesizer.pause()
        state = .paused
        activeReader?.saveProgressNow()
        updateNowPlaying(isPlaying: false)
    }

    func stop() { stop(clearError: true) }

    func previousSegment() {
        guard let index = currentSegmentIndex, !segments.isEmpty else { return }
        move(to: max(index - 1, 0))
    }

    func nextSegment() {
        guard let index = currentSegmentIndex, !segments.isEmpty else { return }
        if index + 1 < segments.count {
            move(to: index + 1)
        } else {
            cancelCurrentUtteranceForTransition()
            finishChapter()
        }
    }

    func selectRate(_ rate: Double) { settingsStore.selectRate(rate) }

    func selectVoice(identifier: String?) { settingsStore.selectVoice(identifier: identifier) }

    func selectContinuousReading(_ enabled: Bool) {
        settingsStore.selectContinuousReading(enabled)
    }

    func selectSleepTimer(_ option: ReaderSleepTimerOption) {
        sleepTask?.cancel()
        sleepTask = nil
        sleepTimerOption = option
        guard let duration = option.duration else { return }
        let sleeper = sleeper
        sleepTask = Task { @MainActor [weak self] in
            do { try await sleeper.sleep(for: duration) }
            catch { return }
            guard !Task.isCancelled else { return }
            self?.stop(clearError: true)
        }
    }

    func readerWillNavigate(_ reader: ReaderViewModel) {
        guard isSession(for: reader) else { return }
        resumeAfterNavigation = state == .speaking || state == .preparing
        pausedWithoutUtterance = state == .paused
        cancelCurrentUtteranceForTransition()
        state = resumeAfterNavigation ? .preparing : .paused
    }

    func readerDidSeek(_ reader: ReaderViewModel) {
        guard isSession(for: reader), reader.content != nil else { return }
        let shouldResume = state == .speaking || state == .preparing
        let shouldRemainPaused = state == .paused
        cancelCurrentUtteranceForTransition()
        guard prepareSegments(from: reader, progress: reader.currentNormalizedProgress) else {
            fail("当前没有可朗读内容")
            return
        }
        if shouldResume {
            speakCurrentSegment()
        } else if shouldRemainPaused {
            pausedWithoutUtterance = true
            state = .paused
        }
    }

    func readerDidLoadContent(_ reader: ReaderViewModel) {
        guard isSession(for: reader) else { return }
        guard state == .preparing || pausedWithoutUtterance else { return }
        guard prepareSegments(from: reader, progress: reader.currentNormalizedProgress) else {
            fail("当前章节无可朗读内容")
            return
        }
        if resumeAfterNavigation {
            resumeAfterNavigation = false
            speakCurrentSegment()
        } else {
            state = .paused
        }
    }

    func readerDidFailLoadingContent(_ reader: ReaderViewModel) {
        guard isSession(for: reader), state == .preparing else { return }
        fail("下一章加载失败")
    }

    private var currentNormalizedProgress: Double {
        guard let index = currentSegmentIndex, segments.indices.contains(index),
              let reader = activeReader else { return 0 }
        let total = max(reader.content?.content.utf16.count ?? 0, 1)
        return min(max(Double(segments[index].startUTF16Offset) / Double(total), 0), 1)
    }

    private func prepareSegments(from reader: ReaderViewModel, progress: Double) -> Bool {
        guard let text = reader.content?.content else { return false }
        let generated = segmenter.segments(in: text)
        guard let index = segmenter.segmentIndex(
            forNormalizedProgress: progress,
            in: generated,
            totalUTF16Length: text.utf16.count
        ) else { return false }
        segments = generated
        currentSegmentIndex = index
        pausedWithoutUtterance = false
        return true
    }

    private func speakCurrentSegment() {
        guard let reader = activeReader,
              let index = currentSegmentIndex,
              segments.indices.contains(index) else {
            fail("当前没有可朗读内容")
            return
        }
        let segment = segments[index]
        state = .preparing
        reader.updateProgressFromSpeech(utf16Offset: segment.startUTF16Offset)
        synthesizer.speak(
            segment,
            rateMultiplier: settingsStore.settings.rate,
            voiceIdentifier: settingsStore.settings.voiceIdentifier
        )
        updateNowPlaying(isPlaying: true)
    }

    private func move(to index: Int) {
        let shouldRemainPaused = state == .paused
        cancelCurrentUtteranceForTransition()
        currentSegmentIndex = min(max(index, 0), max(segments.count - 1, 0))
        if shouldRemainPaused {
            pausedWithoutUtterance = true
            activeReader?.updateProgressFromSpeech(
                utf16Offset: segments[currentSegmentIndex ?? 0].startUTF16Offset
            )
            state = .paused
        } else {
            speakCurrentSegment()
        }
    }

    private func finishChapter() {
        activeReader?.saveProgressNow()
        if sleepTimerOption == .endOfChapter {
            stop(clearError: true)
            return
        }
        guard settingsStore.settings.continuousReading else {
            stop(clearError: true)
            return
        }
        guard let reader = activeReader, reader.nextChapterAvailable else {
            stop(clearError: true)
            speechErrorMessage = "已读完"
            return
        }
        resumeAfterNavigation = true
        state = .preparing
        reader.advanceChapterForSpeech()
    }

    private func handle(_ event: ReaderSpeechEvent) {
        let eventID: UUID
        switch event {
        case let .didStart(id), let .didFinish(id), let .didPause(id),
             let .didContinue(id), let .didCancel(id):
            eventID = id
        }
        if case .didCancel = event, ignoredCancellationIDs.remove(eventID) != nil { return }
        guard let index = currentSegmentIndex,
              segments.indices.contains(index),
              segments[index].id == eventID else { return }

        switch event {
        case .didStart:
            state = .speaking
            updateNowPlaying(isPlaying: true)
        case .didPause:
            state = .paused
            activeReader?.saveProgressNow()
            updateNowPlaying(isPlaying: false)
        case .didContinue:
            state = .speaking
            updateNowPlaying(isPlaying: true)
        case .didCancel:
            if state != .preparing { state = .idle }
        case .didFinish:
            activeReader?.updateProgressFromSpeech(utf16Offset: segments[index].endUTF16Offset)
            if index + 1 < segments.count {
                currentSegmentIndex = index + 1
                speakCurrentSegment()
            } else {
                finishChapter()
            }
        }
    }

    private func handle(_ event: ReaderAudioSessionEvent) {
        guard state == .speaking || state == .preparing else { return }
        pause()
        if event == .interruptionBegan { speechErrorMessage = "朗读已被系统中断" }
    }

    private func handle(_ command: ReaderRemoteCommand) -> Bool {
        switch command {
        case .play:
            guard state == .paused else { return false }
            togglePlaybackFromActiveReader()
        case .pause:
            guard state == .speaking || state == .preparing else { return false }
            pause()
        case .togglePlayPause:
            guard state == .speaking || state == .paused else { return false }
            togglePlaybackFromActiveReader()
        case .next:
            guard state != .idle else { return false }
            nextSegment()
        case .previous:
            guard state != .idle else { return false }
            previousSegment()
        }
        return true
    }

    private func togglePlaybackFromActiveReader() {
        guard let activeReader else { return }
        togglePlayback(from: activeReader)
    }

    private func cancelCurrentUtteranceForTransition() {
        if let index = currentSegmentIndex, segments.indices.contains(index) {
            ignoredCancellationIDs.insert(segments[index].id)
        }
        synthesizer.stop()
    }

    private func updateNowPlaying(isPlaying: Bool) {
        guard let reader = activeReader else { return }
        remoteCommands.updateNowPlaying(
            bookTitle: reader.book.name,
            chapterTitle: reader.currentChapter?.name ?? "",
            isPlaying: isPlaying
        )
    }

    private func stop(clearError: Bool) {
        if clearError { speechErrorMessage = nil }
        cancelCurrentUtteranceForTransition()
        activeReader?.saveProgressNow()
        audioSession.deactivate()
        remoteCommands.clearNowPlaying()
        sleepTask?.cancel()
        sleepTask = nil
        sleepTimerOption = .off
        state = .idle
        segments = []
        currentSegmentIndex = nil
        activeBookID = nil
        resumeAfterNavigation = false
        pausedWithoutUtterance = false
        if visibleReader !== activeReader { activeReader?.cancel() }
        activeReader = nil
        ignoredCancellationIDs.removeAll()
    }

    private func fail(_ message: String) {
        stop(clearError: false)
        speechErrorMessage = message
    }
}
