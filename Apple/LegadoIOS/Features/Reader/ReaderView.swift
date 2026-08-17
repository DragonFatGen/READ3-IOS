import LegadoCore
import SwiftUI

struct ReaderView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @ObservedObject private var settingsStore: ReaderSettingsStore
    @ObservedObject private var speechController: ReaderSpeechController
    @ObservedObject private var speechSettingsStore: ReaderSpeechSettingsStore
    @StateObject private var viewModel: ReaderViewModel
    @State private var controlsVisible = true
    @State private var showsTOC = false
    @State private var showsSettings = false
    @State private var showsBookmarks = false
    @State private var showsSpeechControls = false
    @State private var scrollMetrics = ReaderScrollMetrics.zero
    @State private var sliderProgress = 0.0
    @State private var isEditingProgress = false

    init(
        source: BookSource,
        book: BookInfoResult,
        libraryBookID: String,
        chapters: [BookChapterResult],
        initialChapterIndex: Int,
        contentService: any ChapterContentLoading,
        progressStore: any ReadingProgressStoring,
        bookmarkStore: any BookmarkStoring,
        settingsStore: ReaderSettingsStore,
        paginator: any ReaderPaginating,
        speechController: ReaderSpeechController
    ) {
        _settingsStore = ObservedObject(wrappedValue: settingsStore)
        _speechController = ObservedObject(wrappedValue: speechController)
        _speechSettingsStore = ObservedObject(wrappedValue: speechController.settingsStore)
        _viewModel = StateObject(wrappedValue: ReaderViewModel(
            source: source,
            book: book,
            libraryBookID: libraryBookID,
            chapters: chapters,
            initialChapterIndex: initialChapterIndex,
            contentService: contentService,
            progressStore: progressStore,
            bookmarkStore: bookmarkStore,
            paginator: paginator,
            layoutMode: settingsStore.settings.layoutMode
        ))
    }

    var body: some View {
        GeometryReader { geometry in
            let viewport = ReaderViewport(
                containerSize: geometry.size,
                safeAreaInsets: geometry.safeAreaInsets
            )
            let configuration = paginationConfiguration(for: viewport.contentSize)

            ScrollViewReader { proxy in
                ZStack {
                    settingsStore.settings.theme.backgroundColor.ignoresSafeArea()
                    readerContent(proxy: proxy, viewport: viewport)
                    if controlsVisible { controlsOverlay(viewport: viewport) }
                }
                .animation(.easeInOut(duration: 0.18), value: controlsVisible)
                .toolbar(.hidden, for: .navigationBar)
                .sheet(isPresented: $showsTOC) {
                    ReaderTOCSheet(
                        chapters: viewModel.chapters,
                        currentIndex: viewModel.currentChapterIndex
                    ) { index in
                        showsTOC = false
                        viewModel.goToChapter(at: index)
                    }
                }
                .sheet(isPresented: $showsSettings) {
                    ReaderSettingsSheet(store: settingsStore)
                }
                .sheet(isPresented: $showsBookmarks) {
                    ReaderBookmarksSheet(
                        bookmarks: viewModel.bookmarks,
                        onSelect: { bookmark in
                            showsBookmarks = false
                            viewModel.goToBookmark(bookmark)
                        },
                        onDelete: viewModel.removeBookmark
                    )
                }
                .sheet(isPresented: $showsSpeechControls) {
                    ReaderSpeechControlView(
                        controller: speechController,
                        settingsStore: speechSettingsStore,
                        reader: viewModel
                    )
                }
                .onAppear {
                    speechController.connect(viewModel)
                    sliderProgress = viewModel.chapterProgress
                    viewModel.setLayoutMode(settingsStore.settings.layoutMode)
                    viewModel.updatePaginationConfiguration(configuration)
                }
                .onChange(of: configuration) { value in
                    viewModel.updatePaginationConfiguration(value)
                }
                .onChange(of: settingsStore.settings.layoutMode) { mode in
                    viewModel.setLayoutMode(mode)
                }
                .onChange(of: viewModel.content) { _ in
                    guard viewModel.layoutMode == .scroll else { return }
                    restoreScrollPosition(proxy)
                }
                .onChange(of: viewModel.scrollRestorationID) { _ in
                    restoreScrollPosition(proxy)
                }
                .onChange(of: scrollMetrics) { metrics in
                    guard viewModel.layoutMode == .scroll, viewModel.content != nil else { return }
                    viewModel.updateProgress(metrics.progress)
                }
                .onChange(of: viewModel.chapterProgress) { progress in
                    if !isEditingProgress { sliderProgress = progress }
                }
            }
        }
        .task { viewModel.loadInitialChapter() }
        .onDisappear { speechController.readerDidDisappear(viewModel) }
        .onChange(of: scenePhase) { phase in
            if phase != .active { viewModel.saveProgressNow() }
        }
    }

    @ViewBuilder
    private func readerContent(proxy: ScrollViewProxy, viewport: ReaderViewport) -> some View {
        Group {
            if viewModel.layoutMode == .paged {
                pagedContent(width: viewport.contentSize.width)
            } else {
                scrollContent(proxy: proxy)
            }
        }
        .frame(width: viewport.contentSize.width, height: viewport.contentSize.height)
        .position(x: viewport.center.x, y: viewport.center.y)
    }

    @ViewBuilder
    private func pagedContent(width: CGFloat) -> some View {
        if !viewModel.pages.isEmpty {
            ReaderPagedContentView(
                pages: viewModel.pages,
                currentPageIndex: viewModel.currentPageIndex,
                settings: settingsStore.settings,
                viewportWidth: width,
                canTurnPrevious: viewModel.currentPageIndex > 0
                    || viewModel.previousChapterAvailable,
                canTurnNext: viewModel.currentPageIndex < viewModel.pages.count - 1
                    || viewModel.nextChapterAvailable,
                turnPrevious: viewModel.turnPageBackward,
                turnNext: viewModel.turnPageForward,
                toggleControls: { withAnimation { controlsVisible.toggle() } }
            )
        } else if viewModel.isLoading {
            loadingView
        } else if viewModel.isPaginating {
            ProgressView("正在分页…")
                .tint(settingsStore.settings.theme.foregroundColor)
                .foregroundStyle(settingsStore.settings.theme.foregroundColor)
        } else if let message = viewModel.errorMessage {
            errorView(message)
        } else {
            StatusView(title: "本章暂无正文", message: nil)
        }
    }

    @ViewBuilder
    private func scrollContent(proxy: ScrollViewProxy) -> some View {
        if let result = viewModel.content {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Color.clear.frame(height: 1).id("reader-top")
                    Text(viewModel.currentChapter?.name ?? "")
                        .font(.headline)
                        .foregroundStyle(settingsStore.settings.theme.secondaryColor)
                    Text(result.content)
                        .font(.system(size: CGFloat(settingsStore.settings.fontSize)))
                        .lineSpacing(CGFloat(settingsStore.settings.lineSpacing))
                        .foregroundStyle(settingsStore.settings.theme.foregroundColor)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                        .overlay { restorationAnchors }
                }
                .padding(.horizontal, CGFloat(settingsStore.settings.horizontalPadding))
                .padding(.vertical, ReaderLayoutMetrics.pageVerticalPadding)
                .background(contentMetricsReader)
                .contentShape(Rectangle())
                .simultaneousGesture(TapGesture().onEnded {
                    withAnimation { controlsVisible.toggle() }
                })
            }
            .coordinateSpace(name: "reader-scroll")
            .background(viewportMetricsReader)
            .onPreferenceChange(ReaderContentMetricsKey.self) { content in
                scrollMetrics = ReaderScrollMetrics(
                    offset: max(-content.minY, 0),
                    contentHeight: content.height,
                    viewportHeight: scrollMetrics.viewportHeight
                )
            }
            .onPreferenceChange(ReaderViewportHeightKey.self) { height in
                scrollMetrics.viewportHeight = height
            }
            .onAppear { restoreScrollPosition(proxy) }
        } else if viewModel.isLoading {
            loadingView
        } else if let message = viewModel.errorMessage {
            errorView(message)
        } else {
            StatusView(title: "本章暂无正文", message: nil)
        }
    }

    private var loadingView: some View {
        ProgressView("正在加载正文…")
            .tint(settingsStore.settings.theme.foregroundColor)
            .foregroundStyle(settingsStore.settings.theme.foregroundColor)
    }

    private func errorView(_ message: String) -> some View {
        StatusView(title: "章节加载失败", message: message, retry: viewModel.retry)
            .foregroundStyle(settingsStore.settings.theme.foregroundColor)
    }

    private func controlsOverlay(viewport: ReaderViewport) -> some View {
        VStack(spacing: 0) {
            topControls
                .padding(.top, viewport.safeAreaInsets.top)
            Spacer()
            bottomControls
                .padding(.bottom, viewport.safeAreaInsets.bottom)
        }
        .ignoresSafeArea()
    }

    private var topControls: some View {
        HStack(spacing: 12) {
            Button { dismiss() } label: {
                Label("返回", systemImage: "chevron.left").labelStyle(.iconOnly)
            }
            .accessibilityLabel("返回")
            VStack(alignment: .leading, spacing: 2) {
                Text(viewModel.book.name).font(.headline).lineLimit(1)
                Text(viewModel.currentChapter?.name ?? "").font(.caption).lineLimit(1)
            }
            Spacer()
            Button { viewModel.toggleBookmark() } label: {
                Label(
                    viewModel.isCurrentPositionBookmarked ? "删除当前位置书签" : "添加当前位置书签",
                    systemImage: viewModel.isCurrentPositionBookmarked ? "bookmark.fill" : "bookmark"
                ).labelStyle(.iconOnly)
            }
            .accessibilityLabel(viewModel.isCurrentPositionBookmarked ? "删除当前位置书签" : "添加当前位置书签")
            Menu {
                Button { showsTOC = true } label: { Label("目录", systemImage: "list.bullet") }
                Button { showsBookmarks = true } label: { Label("书签列表", systemImage: "bookmark.square") }
                Button { showsSettings = true } label: { Label("阅读设置", systemImage: "textformat.size") }
                Button { showsSpeechControls = true } label: {
                    Label("朗读控制", systemImage: "speaker.wave.2")
                }
                Button { viewModel.reloadCurrentChapter() } label: {
                    Label("重新加载本章", systemImage: "arrow.clockwise")
                }
                .disabled(viewModel.isLoading)
            } label: {
                Label("更多阅读操作", systemImage: "ellipsis.circle").labelStyle(.iconOnly)
            }
            .accessibilityLabel("更多阅读操作")
        }
        .padding(.horizontal)
        .frame(minHeight: ReaderLayoutMetrics.topControlBarHeight)
        .foregroundStyle(settingsStore.settings.theme.foregroundColor)
        .background(.ultraThinMaterial)
    }

    private var bottomControls: some View {
        VStack(spacing: 6) {
            if speechController.isSession(for: viewModel) {
                HStack(spacing: 18) {
                    controlButton("上一句", icon: "backward.end.fill", action: speechController.previousSegment)
                    controlButton(
                        speechController.state == .paused ? "继续朗读" : "暂停朗读",
                        icon: speechController.state == .paused ? "play.fill" : "pause.fill"
                    ) { speechController.togglePlayback(from: viewModel) }
                    controlButton("下一句", icon: "forward.end.fill", action: speechController.nextSegment)
                    controlButton("停止朗读", icon: "stop.fill", action: speechController.stop)
                    Button(speechController.currentRateText) { showsSpeechControls = true }
                        .accessibilityLabel("朗读语速 " + speechController.currentRateText)
                }
            } else {
                Button {
                    showsSpeechControls = true
                } label: {
                    Label("朗读", systemImage: "speaker.wave.2")
                }
                .accessibilityLabel("开始朗读")
            }
            HStack(spacing: 10) {
                Slider(
                    value: Binding<Double>(
                        get: { sliderProgress },
                        set: { sliderProgress = min(max($0, 0), 1) }
                    ),
                    in: 0...1,
                    onEditingChanged: { editing in
                        isEditingProgress = editing
                        if !editing { viewModel.seek(to: sliderProgress) }
                    }
                )
                .accessibilityLabel("本章进度快速定位")
                Text(sliderProgress, format: .percent.precision(.fractionLength(0)))
                    .frame(minWidth: 36, alignment: .trailing)
                    .accessibilityLabel("本章阅读进度")
            }
            HStack {
                controlButton("上一章", icon: "chevron.left", action: viewModel.goToPreviousChapter)
                    .disabled(!viewModel.previousChapterAvailable)
                Spacer()
                controlButton("目录", icon: "list.bullet") { showsTOC = true }
                Spacer()
                if let page = viewModel.pageProgressText {
                    Text(page).accessibilityLabel("本章页码")
                } else {
                    Text(viewModel.currentChapter?.name ?? "").lineLimit(1)
                }
                Spacer()
                controlButton("书签列表", icon: "bookmark.square") { showsBookmarks = true }
                Spacer()
                controlButton("下一章", icon: "chevron.right", action: viewModel.goToNextChapter)
                    .disabled(!viewModel.nextChapterAvailable)
            }
        }
        .font(.caption.monospacedDigit())
        .padding(.horizontal)
        .frame(minHeight: ReaderLayoutMetrics.bottomControlBarHeight)
        .foregroundStyle(settingsStore.settings.theme.foregroundColor)
        .background(.ultraThinMaterial)
    }

    private func controlButton(_ title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) { Label(title, systemImage: icon) }
            .accessibilityLabel(title)
    }

    private func paginationConfiguration(for size: CGSize) -> PaginationConfiguration {
        PaginationConfiguration(
            size: size,
            fontSize: CGFloat(settingsStore.settings.fontSize),
            lineSpacing: CGFloat(settingsStore.settings.lineSpacing),
            horizontalPadding: CGFloat(settingsStore.settings.horizontalPadding),
            verticalPadding: ReaderLayoutMetrics.pageVerticalPadding
        )
    }

    private func restoreScrollPosition(_ proxy: ScrollViewProxy) {
        guard viewModel.layoutMode == .scroll, viewModel.content != nil else { return }
        let progress = viewModel.consumeRestorationProgress() ?? 0
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            proxy.scrollTo(
                progress > 0
                    ? "reader-progress-\(Int((progress * 100).rounded()))"
                    : "reader-top",
                anchor: .top
            )
        }
    }

    private var restorationAnchors: some View {
        GeometryReader { geometry in
            ZStack(alignment: .topLeading) {
                ForEach(0...100, id: \.self) { value in
                    Color.clear
                        .frame(width: 1, height: 1)
                        .offset(y: geometry.size.height * CGFloat(value) / 100)
                        .id("reader-progress-\(value)")
                }
            }
        }
        .allowsHitTesting(false)
    }

    private var contentMetricsReader: some View {
        GeometryReader { geometry in
            let frame = geometry.frame(in: .named("reader-scroll"))
            Color.clear.preference(
                key: ReaderContentMetricsKey.self,
                value: ReaderContentMetrics(minY: frame.minY, height: frame.height)
            )
        }
    }

    private var viewportMetricsReader: some View {
        GeometryReader { geometry in
            Color.clear.preference(key: ReaderViewportHeightKey.self, value: geometry.size.height)
        }
    }
}

private enum ReaderLayoutMetrics {
    static let topControlBarHeight: CGFloat = 52
    static let bottomControlBarHeight: CGFloat = 132
    static let pageVerticalPadding: CGFloat = 20
}

private struct ReaderViewport {
    let containerSize: CGSize
    let safeAreaInsets: EdgeInsets

    var contentSize: CGSize {
        CGSize(
            width: max(containerSize.width - safeAreaInsets.leading - safeAreaInsets.trailing, 1),
            height: max(
                containerSize.height - safeAreaInsets.top - safeAreaInsets.bottom
                    - ReaderLayoutMetrics.topControlBarHeight
                    - ReaderLayoutMetrics.bottomControlBarHeight,
                1
            )
        )
    }

    var center: CGPoint {
        CGPoint(
            x: safeAreaInsets.leading + contentSize.width / 2,
            y: safeAreaInsets.top + ReaderLayoutMetrics.topControlBarHeight + contentSize.height / 2
        )
    }
}

private struct ReaderContentMetrics: Equatable {
    var minY: CGFloat
    var height: CGFloat
}

private struct ReaderScrollMetrics: Equatable {
    var offset: CGFloat
    var contentHeight: CGFloat
    var viewportHeight: CGFloat

    static let zero = ReaderScrollMetrics(offset: 0, contentHeight: 0, viewportHeight: 0)

    var progress: Double {
        let distance = max(contentHeight - viewportHeight, 1)
        return min(max(Double(offset / distance), 0), 1)
    }
}

private struct ReaderContentMetricsKey: PreferenceKey {
    static let defaultValue = ReaderContentMetrics(minY: 0, height: 0)
    static func reduce(value: inout ReaderContentMetrics, nextValue: () -> ReaderContentMetrics) {
        value = nextValue()
    }
}

private struct ReaderViewportHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}
