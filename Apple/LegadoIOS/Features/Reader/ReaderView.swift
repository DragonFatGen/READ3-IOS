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
        settingsStore: ReaderSettingsStore,
        paginator: any ReaderPaginating
    ) {
        _settingsStore = ObservedObject(wrappedValue: settingsStore)
        _viewModel = StateObject(wrappedValue: ReaderViewModel(
            source: source,
            book: book,
            libraryBookID: libraryBookID,
            chapters: chapters,
            initialChapterIndex: initialChapterIndex,
            contentService: contentService,
            progressStore: progressStore,
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
                .onAppear {
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
            }
        }
        .task { viewModel.loadInitialChapter() }
        .onDisappear { viewModel.cancel() }
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
            TabView(selection: Binding<Int>(
                get: { viewModel.currentPageIndex },
                set: { page in viewModel.selectPage(page) }
            )) {
                ForEach(viewModel.pages) { page in
                    Text(page.text)
                        .font(.system(size: CGFloat(settingsStore.settings.fontSize)))
                        .lineSpacing(CGFloat(settingsStore.settings.lineSpacing))
                        .foregroundStyle(settingsStore.settings.theme.foregroundColor)
                        .padding(.horizontal, CGFloat(settingsStore.settings.horizontalPadding))
                        .padding(.vertical, ReaderLayoutMetrics.pageVerticalPadding)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                        .tag(page.index)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .contentShape(Rectangle())
            .simultaneousGesture(SpatialTapGesture().onEnded { value in
                handlePageTap(value, width: width)
            })
            .simultaneousGesture(DragGesture(minimumDistance: ReaderLayoutMetrics.swipeThreshold)
                .onEnded { value in handleBoundarySwipe(value) })
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
            Button { viewModel.reloadCurrentChapter() } label: {
                Label("重新加载本章", systemImage: "arrow.clockwise").labelStyle(.iconOnly)
            }
            .disabled(viewModel.isLoading)
            .accessibilityLabel("重新加载本章")
            Button { showsSettings = true } label: {
                Label("阅读设置", systemImage: "textformat.size").labelStyle(.iconOnly)
            }
            .accessibilityLabel("阅读设置")
        }
        .padding(.horizontal)
        .frame(minHeight: ReaderLayoutMetrics.controlBarHeight)
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
            if let page = viewModel.pageProgressText {
                Text(page).accessibilityLabel("本章页码")
            } else {
                Text(viewModel.chapterProgress, format: .percent.precision(.fractionLength(0)))
                    .accessibilityLabel("本章阅读进度")
            }
            Spacer()
            controlButton("下一章", icon: "chevron.right", action: viewModel.goToNextChapter)
                .disabled(!viewModel.nextChapterAvailable)
        }
        .font(.caption.monospacedDigit())
        .padding(.horizontal)
        .frame(minHeight: ReaderLayoutMetrics.controlBarHeight)
        .foregroundStyle(settingsStore.settings.theme.foregroundColor)
        .background(.ultraThinMaterial)
    }

    private func controlButton(_ title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) { Label(title, systemImage: icon) }
            .accessibilityLabel(title)
    }

    private func handlePageTap(_ value: SpatialTapGesture.Value, width: CGFloat) {
        let horizontalRatio = min(max(value.location.x / max(width, 1), 0), 1)
        if horizontalRatio < ReaderLayoutMetrics.sideTapRatio {
            viewModel.turnPageBackward()
        } else if horizontalRatio > 1 - ReaderLayoutMetrics.sideTapRatio {
            viewModel.turnPageForward()
        } else {
            withAnimation { controlsVisible.toggle() }
        }
    }

    private func handleBoundarySwipe(_ value: DragGesture.Value) {
        guard abs(value.translation.width) > abs(value.translation.height) else { return }
        if value.translation.width < -ReaderLayoutMetrics.swipeThreshold,
           viewModel.currentPageIndex == viewModel.pages.count - 1 {
            viewModel.turnPageForward()
        } else if value.translation.width > ReaderLayoutMetrics.swipeThreshold,
                  viewModel.currentPageIndex == 0 {
            viewModel.turnPageBackward()
        }
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
    static let controlBarHeight: CGFloat = 52
    static let pageVerticalPadding: CGFloat = 20
    static let sideTapRatio: CGFloat = 0.30
    static let swipeThreshold: CGFloat = 40
}

private struct ReaderViewport {
    let containerSize: CGSize
    let safeAreaInsets: EdgeInsets

    var contentSize: CGSize {
        CGSize(
            width: max(containerSize.width - safeAreaInsets.leading - safeAreaInsets.trailing, 1),
            height: max(
                containerSize.height - safeAreaInsets.top - safeAreaInsets.bottom
                    - ReaderLayoutMetrics.controlBarHeight * 2,
                1
            )
        )
    }

    var center: CGPoint {
        CGPoint(
            x: safeAreaInsets.leading + contentSize.width / 2,
            y: safeAreaInsets.top + ReaderLayoutMetrics.controlBarHeight + contentSize.height / 2
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
