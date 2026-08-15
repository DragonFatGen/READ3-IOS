import LegadoCore
import SwiftUI

struct ReaderView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @ObservedObject private var settingsStore: ReaderSettingsStore
    @StateObject private var viewModel: ReaderViewModel
    @State private var controlsVisible = true
    @State private var showsTOC = false
    @State private var showsSettings = false
    @State private var scrollMetrics = ReaderScrollMetrics.zero

    init(
        source: BookSource,
        book: BookInfoResult,
        libraryBookID: String,
        chapters: [BookChapterResult],
        initialChapterIndex: Int,
        contentService: any ChapterContentLoading,
        progressStore: any ReadingProgressStoring,
        settingsStore: ReaderSettingsStore
    ) {
        _settingsStore = ObservedObject(wrappedValue: settingsStore)
        _viewModel = StateObject(wrappedValue: ReaderViewModel(
            source: source,
            book: book,
            libraryBookID: libraryBookID,
            chapters: chapters,
            initialChapterIndex: initialChapterIndex,
            contentService: contentService,
            progressStore: progressStore
        ))
    }

    var body: some View {
        ScrollViewReader { proxy in
            ZStack {
                settingsStore.settings.theme.backgroundColor.ignoresSafeArea()
                readerContent(proxy: proxy)
            }
            .safeAreaInset(edge: .top, spacing: 0) {
                if controlsVisible { topControls }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if controlsVisible { bottomControls }
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
            .onChange(of: viewModel.content) { _ in
                restoreOrScrollToTop(proxy)
            }
            .onChange(of: scrollMetrics) { metrics in
                guard viewModel.content != nil else { return }
                viewModel.updateProgress(metrics.progress)
            }
        }
        .task { viewModel.loadInitialChapter() }
        .onDisappear { viewModel.cancel() }
        .onChange(of: scenePhase) { phase in
            if phase != .active { viewModel.saveProgressNow() }
        }
    }

    @ViewBuilder
    private func readerContent(proxy: ScrollViewProxy) -> some View {
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
                .padding(.vertical, 18)
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
        } else if viewModel.isLoading {
            ProgressView("正在加载正文…")
                .tint(settingsStore.settings.theme.foregroundColor)
                .foregroundStyle(settingsStore.settings.theme.foregroundColor)
        } else if let message = viewModel.errorMessage {
            StatusView(title: "章节加载失败", message: message, retry: viewModel.retry)
                .foregroundStyle(settingsStore.settings.theme.foregroundColor)
        } else {
            StatusView(title: "没有可阅读章节", message: nil)
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
            Button { showsSettings = true } label: {
                Label("阅读设置", systemImage: "textformat.size")
                    .labelStyle(.iconOnly)
            }
            .accessibilityLabel("阅读设置")
        }
        .padding(.horizontal)
        .padding(.vertical, 10)
        .foregroundStyle(settingsStore.settings.theme.foregroundColor)
        .background(.ultraThinMaterial)
    }

    private var bottomControls: some View {
        HStack {
            controlButton("上一章", icon: "chevron.left", action: viewModel.goToPreviousChapter)
                .disabled(!viewModel.previousChapterAvailable)
            Spacer()
            controlButton("目录", icon: "list.bullet") { showsTOC = true }
            Spacer()
            Text(viewModel.chapterProgress, format: .percent.precision(.fractionLength(0)))
                .font(.caption.monospacedDigit())
                .accessibilityLabel("本章阅读进度")
            Spacer()
            controlButton("下一章", icon: "chevron.right", action: viewModel.goToNextChapter)
                .disabled(!viewModel.nextChapterAvailable)
        }
        .padding(.horizontal)
        .padding(.vertical, 10)
        .foregroundStyle(settingsStore.settings.theme.foregroundColor)
        .background(.ultraThinMaterial)
    }

    private func controlButton(_ title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: icon).labelStyle(.titleAndIcon)
        }
        .accessibilityLabel(title)
    }

    private func restoreOrScrollToTop(_ proxy: ScrollViewProxy) {
        guard viewModel.content != nil else { return }
        let progress = viewModel.consumeRestorationProgress() ?? 0
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            if progress > 0 {
                proxy.scrollTo("reader-progress-\(Int((progress * 100).rounded()))", anchor: .top)
            } else {
                proxy.scrollTo("reader-top", anchor: .top)
            }
        }
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
