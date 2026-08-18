import LegadoCore
import XCTest
@testable import LegadoIOS

@MainActor
final class ReaderSpeechControllerTests: XCTestCase {
    func testPlayStartsAtCurrentProgressSegment() async {
        let fixture = makeFixture()
        await fixture.load()
        fixture.reader.seek(to: 0.45)
        fixture.controller.start(from: fixture.reader)
        XCTAssertEqual(fixture.synthesizer.spoken.last?.text, "第二句比较长。")
        XCTAssertEqual(fixture.controller.state, .speaking)
    }

    func testPauseResumeAndStopStateTransitions() async {
        let fixture = makeFixture()
        await fixture.loadAndStart()
        fixture.controller.pause()
        XCTAssertEqual(fixture.controller.state, .paused)
        fixture.controller.togglePlayback(from: fixture.reader)
        XCTAssertEqual(fixture.controller.state, .speaking)
        let progress = fixture.reader.chapterProgress
        fixture.controller.stop()
        XCTAssertEqual(fixture.controller.state, .idle)
        XCTAssertEqual(fixture.reader.chapterProgress, progress)
    }

    func testNextAndPreviousSegment() async {
        let fixture = makeFixture()
        await fixture.loadAndStart()
        fixture.controller.nextSegment()
        XCTAssertEqual(fixture.synthesizer.spoken.last?.text, "第二句比较长。")
        fixture.controller.previousSegment()
        XCTAssertEqual(fixture.synthesizer.spoken.last?.text, "第一句。")
    }

    func testPreviousAtFirstSegmentClamps() async {
        let fixture = makeFixture()
        await fixture.loadAndStart()
        fixture.controller.previousSegment()
        XCTAssertEqual(fixture.controller.currentSegmentIndex, 0)
        XCTAssertEqual(fixture.synthesizer.spoken.last?.text, "第一句。")
    }

    func testFinishingSegmentAdvancesProgressByUTF16Offset() async {
        let fixture = makeFixture()
        await fixture.loadAndStart()
        fixture.synthesizer.finishCurrent()
        XCTAssertEqual(fixture.controller.currentSegmentIndex, 1)
        XCTAssertGreaterThan(fixture.reader.chapterProgress, 0)
    }

    func testContinuousReadingLoadsNextChapterAndStartsFirstSegment() async {
        let fixture = makeFixture(chapterCount: 2)
        await fixture.loadAndStart()
        fixture.synthesizer.finishAllCurrentChapterSegments(count: 3)
        await waitUntil { fixture.reader.currentChapterIndex == 1 && fixture.synthesizer.spoken.last?.text == "第一句。" }
        XCTAssertEqual(fixture.reader.currentChapterIndex, 1)
        XCTAssertEqual(fixture.controller.currentSegmentIndex, 0)
    }

    func testContinuousReadingDisabledStopsAtChapterBoundary() async {
        let fixture = makeFixture(chapterCount: 2)
        fixture.settings.selectContinuousReading(false)
        await fixture.loadAndStart()
        fixture.synthesizer.finishAllCurrentChapterSegments(count: 3)
        XCTAssertEqual(fixture.controller.state, .idle)
        XCTAssertEqual(fixture.reader.currentChapterIndex, 0)
    }

    func testLastBookChapterStopsWithoutLooping() async {
        let fixture = makeFixture(chapterCount: 1)
        await fixture.loadAndStart()
        fixture.synthesizer.finishAllCurrentChapterSegments(count: 3)
        XCTAssertEqual(fixture.controller.state, .idle)
        XCTAssertEqual(fixture.controller.speechErrorMessage, "已读完")
    }

    func testNextChapterFailureStopsWithFriendlyError() async {
        let fixture = makeFixture(chapterCount: 2, failingChapter: 1)
        await fixture.loadAndStart()
        fixture.synthesizer.finishAllCurrentChapterSegments(count: 3)
        await waitUntil { fixture.controller.speechErrorMessage != nil }
        XCTAssertEqual(fixture.controller.state, .idle)
        XCTAssertEqual(fixture.controller.speechErrorMessage, "下一章加载失败")
    }

    func testEmptyContentDoesNotActivateAudio() async {
        let fixture = makeFixture(content: " \n ")
        await fixture.load()
        fixture.controller.start(from: fixture.reader)
        XCTAssertEqual(fixture.controller.state, .idle)
        XCTAssertEqual(fixture.controller.speechErrorMessage, "当前没有可朗读内容")
        XCTAssertEqual(fixture.audio.activationCount, 0)
    }

    func testPlayActivatesAndStopDeactivatesAudioSession() async {
        let fixture = makeFixture()
        await fixture.loadAndStart()
        XCTAssertEqual(fixture.audio.activationCount, 1)
        fixture.controller.stop()
        XCTAssertEqual(fixture.audio.deactivationCount, 1)
    }

    func testInterruptionPausesAndDoesNotAutoResume() async {
        let fixture = makeFixture()
        await fixture.loadAndStart()
        fixture.audio.send(.interruptionBegan)
        XCTAssertEqual(fixture.controller.state, .paused)
        XCTAssertEqual(fixture.controller.speechErrorMessage, "朗读已被系统中断")
    }

    func testHeadphonesRemovedPauses() async {
        let fixture = makeFixture()
        await fixture.loadAndStart()
        fixture.audio.send(.headphonesRemoved)
        XCTAssertEqual(fixture.controller.state, .paused)
    }

    func testRemoteCommandsControlPlaybackAndSegments() async {
        let fixture = makeFixture()
        await fixture.loadAndStart()
        XCTAssertTrue(fixture.remote.send(.pause))
        XCTAssertEqual(fixture.controller.state, .paused)
        XCTAssertTrue(fixture.remote.send(.play))
        XCTAssertTrue(fixture.remote.send(.next))
        XCTAssertEqual(fixture.controller.currentSegmentIndex, 1)
        XCTAssertTrue(fixture.remote.send(.previous))
        XCTAssertEqual(fixture.controller.currentSegmentIndex, 0)
    }

    func testNowPlayingUsesBookAndChapterNamesAndClearsOnStop() async {
        let fixture = makeFixture()
        await fixture.loadAndStart()
        XCTAssertEqual(fixture.remote.bookTitle, testBookInfo().name)
        XCTAssertEqual(fixture.remote.chapterTitle, testChapter().name)
        fixture.controller.stop()
        XCTAssertTrue(fixture.remote.didClear)
    }

    func testTimerStartsChangingCancelsOldAndOffCancelsTimer() async {
        let fixture = makeFixture()
        await fixture.loadAndStart()
        fixture.controller.selectSleepTimer(.fifteenMinutes)
        for _ in 0..<300 {
            if await fixture.sleeper.callCount == 1 { break }
            try? await Task.sleep(for: .milliseconds(2))
        }
        fixture.controller.selectSleepTimer(.sixtyMinutes)
        for _ in 0..<300 {
            if await fixture.sleeper.callCount == 2 { break }
            try? await Task.sleep(for: .milliseconds(2))
        }
        let callCount = await fixture.sleeper.callCount
        XCTAssertEqual(callCount, 2)
        fixture.controller.selectSleepTimer(.off)
        XCTAssertEqual(fixture.controller.sleepTimerOption, .off)
    }

    func testTimerExpiryStopsSpeech() async {
        let fixture = makeFixture()
        await fixture.loadAndStart()
        fixture.controller.selectSleepTimer(.fifteenMinutes)

        for _ in 0..<300 {
            if await fixture.sleeper.hasPendingSleep() {
                break
            }
            try? await Task.sleep(for: .milliseconds(2))
        }

        let hasPendingSleep = await fixture.sleeper.hasPendingSleep()
        XCTAssertTrue(hasPendingSleep)
        await fixture.sleeper.expireAll()
        await waitUntil { fixture.controller.state == .idle }
        XCTAssertEqual(fixture.controller.state, .idle)
    }

    func testEndOfChapterTimerStopsWithoutChangingContinuousSetting() async {
        let fixture = makeFixture(chapterCount: 2)
        await fixture.loadAndStart()
        fixture.controller.selectSleepTimer(.endOfChapter)
        fixture.synthesizer.finishAllCurrentChapterSegments(count: 3)
        XCTAssertEqual(fixture.controller.state, .idle)
        XCTAssertTrue(fixture.settings.settings.continuousReading)
    }

    func testPagedReaderFollowsSpeechWithoutPageTurnAPI() async {
        let fixture = makeFixture(layoutMode: .paged)
        fixture.reader.updatePaginationConfiguration(PaginationConfiguration(
            size: CGSize(width: 320, height: 480), fontSize: 19, lineSpacing: 8,
            horizontalPadding: 20, verticalPadding: 20
        ))
        await fixture.load()
        await waitUntil { fixture.reader.pages.count == 3 }
        fixture.controller.start(from: fixture.reader)
        fixture.controller.nextSegment()
        XCTAssertEqual(fixture.reader.currentPageIndex, 1)
    }

    func testVisualPageTurnDoesNotSeekSpeechCursor() async {
        let fixture = makeFixture(layoutMode: .paged)
        fixture.reader.updatePaginationConfiguration(PaginationConfiguration(
            size: CGSize(width: 320, height: 480), fontSize: 19, lineSpacing: 8,
            horizontalPadding: 20, verticalPadding: 20
        ))
        await fixture.load()
        await waitUntil { fixture.reader.pages.count == 3 }
        fixture.controller.start(from: fixture.reader)
        fixture.reader.selectPage(2)
        XCTAssertEqual(fixture.controller.currentSegmentIndex, 0)
    }

    func testSliderSeekRebuildsSpeechCursorAndContinues() async {
        let fixture = makeFixture()
        await fixture.loadAndStart()
        fixture.reader.seek(to: 0.8)
        XCTAssertEqual(fixture.synthesizer.spoken.last?.text, "第三句。")
        XCTAssertEqual(fixture.controller.state, .speaking)
    }

    func testStaleOldSegmentCompletionIsIgnored() async {
        let fixture = makeFixture()
        await fixture.loadAndStart()
        let oldID = fixture.synthesizer.spoken[0].id
        fixture.controller.nextSegment()
        fixture.synthesizer.emitFinish(id: oldID)
        XCTAssertEqual(fixture.controller.currentSegmentIndex, 1)
        XCTAssertEqual(fixture.reader.currentChapterIndex, 0)
    }

    func testCancellationDoesNotAutoSwitchChapter() async {
        let fixture = makeFixture(chapterCount: 2)
        await fixture.loadAndStart()
        let oldID = fixture.synthesizer.spoken[0].id
        fixture.controller.stop()
        fixture.synthesizer.emitFinish(id: oldID)
        XCTAssertEqual(fixture.controller.state, .idle)
        XCTAssertEqual(fixture.reader.currentChapterIndex, 0)
    }

    func testChapterJumpWhilePausedKeepsPausedAtNewPosition() async {
        let fixture = makeFixture(chapterCount: 2)
        await fixture.loadAndStart()
        fixture.controller.pause()
        fixture.reader.goToChapter(at: 1)
        await waitUntil { fixture.reader.content != nil && fixture.reader.currentChapterIndex == 1 }
        XCTAssertEqual(fixture.controller.state, .paused)
        fixture.controller.togglePlayback(from: fixture.reader)
        XCTAssertEqual(fixture.synthesizer.spoken.last?.text, "第一句。")
    }

    func testReaderExitKeepsActiveSpeechSession() async {
        let fixture = makeFixture()
        await fixture.loadAndStart()
        fixture.controller.readerDidDisappear(fixture.reader)
        XCTAssertEqual(fixture.controller.state, .speaking)
        XCTAssertTrue(fixture.controller.isSession(for: fixture.reader))
    }

    func testStartingAnotherBookStopsPreviousSession() async {
        let fixture = makeFixture()
        await fixture.loadAndStart()
        let other = makeFixture(bookID: "other")
        await other.load()
        fixture.controller.connect(other.reader)
        fixture.controller.start(from: other.reader)
        XCTAssertTrue(fixture.controller.isSession(for: other.reader))
        XCTAssertFalse(fixture.controller.isSession(for: fixture.reader))
    }

    private func makeFixture(
        bookID: String = "book",
        chapterCount: Int = 3,
        content: String = "第一句。第二句比较长。第三句。",
        failingChapter: Int? = nil,
        layoutMode: ReaderLayoutMode = .scroll
    ) -> SpeechFixture {
        let synthesizer = FakeSpeechSynthesizer()
        let audio = FakeAudioSession()
        let remote = FakeRemoteCommands()
        let sleeper = TestSpeechSleeper()
        let defaults = UserDefaults(suiteName: "ReaderSpeechControllerTests.\(UUID().uuidString)")!
        let settings = ReaderSpeechSettingsStore(defaults: defaults, keyPrefix: "tts")
        let controller = ReaderSpeechController(
            synthesizer: synthesizer,
            audioSession: audio,
            remoteCommands: remote,
            settingsStore: settings,
            sleeper: sleeper
        )
        let service = SpeechContentService(content: content, failingChapter: failingChapter)
        let progress = SpeechProgressStore()
        let reader = ReaderViewModel(
            source: testSource(), book: testBookInfo(), libraryBookID: bookID,
            chapters: (0..<chapterCount).map(testChapter), initialChapterIndex: 0,
            contentService: service, progressStore: progress,
            paginator: SpeechPaginator(), layoutMode: layoutMode
        )
        controller.connect(reader)
        return SpeechFixture(
            reader: reader, controller: controller, synthesizer: synthesizer,
            audio: audio, remote: remote, sleeper: sleeper, settings: settings,
            progress: progress
        )
    }

    private func waitUntil(
        attempts: Int = 300,
        condition: @MainActor () -> Bool
    ) async {
        for _ in 0..<attempts {
            if condition() { return }
            try? await Task.sleep(for: .milliseconds(2))
        }
        XCTFail("Timed out waiting for speech state")
    }
}

@MainActor
private struct SpeechFixture {
    let reader: ReaderViewModel
    let controller: ReaderSpeechController
    let synthesizer: FakeSpeechSynthesizer
    let audio: FakeAudioSession
    let remote: FakeRemoteCommands
    let sleeper: TestSpeechSleeper
    let settings: ReaderSpeechSettingsStore
    let progress: SpeechProgressStore

    func load() async {
        reader.loadInitialChapter()
        for _ in 0..<300 {
            if reader.content != nil || reader.errorMessage != nil { return }
            try? await Task.sleep(for: .milliseconds(2))
        }
    }

    func loadAndStart() async {
        await load()
        controller.start(from: reader)
    }
}

@MainActor
private final class FakeSpeechSynthesizer: ReaderSpeechSynthesizing {
    var eventHandler: ((ReaderSpeechEvent) -> Void)?
    let availableVoices = [ReaderSpeechVoice(id: "zh", name: "中文", language: "zh-CN")]
    private(set) var spoken: [ReaderSpeechSegment] = []
    private var current: ReaderSpeechSegment?

    func speak(_ segment: ReaderSpeechSegment, rateMultiplier: Double, voiceIdentifier: String?) {
        _ = rateMultiplier
        _ = voiceIdentifier
        current = segment
        spoken.append(segment)
        eventHandler?(.didStart(segment.id))
    }

    func pause() {
        if let current { eventHandler?(.didPause(current.id)) }
    }

    func resume() {
        if let current { eventHandler?(.didContinue(current.id)) }
    }

    func stop() {
        if let current { eventHandler?(.didCancel(current.id)) }
        current = nil
    }

    func finishCurrent() {
        guard let value = current else { return }
        current = nil
        eventHandler?(.didFinish(value.id))
    }

    func finishAllCurrentChapterSegments(count: Int) {
        for _ in 0..<count { finishCurrent() }
    }

    func emitFinish(id: UUID) { eventHandler?(.didFinish(id)) }
}

@MainActor
private final class FakeAudioSession: ReaderAudioSessionManaging {
    var eventHandler: ((ReaderAudioSessionEvent) -> Void)?
    private(set) var activationCount = 0
    private(set) var deactivationCount = 0
    func activate() throws { activationCount += 1 }
    func deactivate() { deactivationCount += 1 }
    func send(_ event: ReaderAudioSessionEvent) { eventHandler?(event) }
}

@MainActor
private final class FakeRemoteCommands: ReaderRemoteCommandManaging {
    var commandHandler: ((ReaderRemoteCommand) -> Bool)?
    private(set) var bookTitle: String?
    private(set) var chapterTitle: String?
    private(set) var didClear = false
    func updateNowPlaying(bookTitle: String, chapterTitle: String, isPlaying: Bool) {
        self.bookTitle = bookTitle
        self.chapterTitle = chapterTitle
        didClear = false
    }
    func clearNowPlaying() { didClear = true }
    func send(_ command: ReaderRemoteCommand) -> Bool { commandHandler?(command) ?? false }
}

private actor TestSpeechSleeper: ReaderSpeechSleeping {
    private var continuations: [UUID: CheckedContinuation<Void, Error>] = [:]
    private(set) var callCount = 0

    func sleep(for duration: Duration) async throws {
        _ = duration
        callCount += 1
        let id = UUID()
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                continuations[id] = continuation
            }
        } onCancel: {
            Task { await self.cancel(id: id) }
        }
    }

    func expireAll() {
        let values = Array(continuations.values)
        continuations = [:]
        values.forEach { $0.resume() }
    }

    func hasPendingSleep() -> Bool {
        !continuations.isEmpty
    }

    private func cancel(id: UUID) {
        continuations.removeValue(forKey: id)?.resume(throwing: CancellationError())
    }
}

@MainActor
private final class SpeechProgressStore: ReadingProgressStoring {
    private(set) var value: ReadingProgress?
    func progress(for bookID: String) -> ReadingProgress? { value }
    func saveProgress(_ progress: ReadingProgress, for bookID: String) { value = progress }
}

private actor SpeechContentService: ChapterContentLoading {
    let content: String
    let failingChapter: Int?
    init(content: String, failingChapter: Int?) {
        self.content = content
        self.failingChapter = failingChapter
    }
    func loadContent(
        source: BookSource,
        book: BookInfoResult,
        chapter: BookChapterResult,
        policy: ContentLoadPolicy
    ) async throws -> ChapterContentResult {
        _ = policy
        if chapter.index == failingChapter { throw ViewModelTestError.expected }
        return ChapterContentResult(content: content, chapterURL: chapter.url)
    }
}

private actor SpeechPaginator: ReaderPaginating {
    func paginate(text: String, configuration: PaginationConfiguration) async -> [ReaderPage] {
        _ = configuration
        return ReaderSpeechSegmenter().segments(in: text).enumerated().map { index, segment in
            ReaderPage(
                index: index,
                utf16Range: segment.startUTF16Offset..<segment.endUTF16Offset,
                text: "page \(index + 1)"
            )
        }
    }
}
