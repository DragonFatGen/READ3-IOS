import SwiftUI

struct BookshelfView: View {
    @ObservedObject var repository: LibraryRepository
    let dependencies: AppDependencies
    @StateObject private var sortPreference = LibrarySortPreference()
    @State private var filter: LibraryFilter = .all
    @ObservedObject private var viewModel: LibraryViewModel
    @State private var pendingDeletion: LibraryBook?
    @State private var showsUpdateSettings = false
    @State private var showsUpdateSummary = false

    init(repository: LibraryRepository, dependencies: AppDependencies) {
        self.repository = repository
        self.dependencies = dependencies
        viewModel = dependencies.libraryViewModel
    }

    private var displayedBooks: [LibraryBook] {
        repository.books.filter { $0.matches(filter) }.sorted(by: sortPreference.mode)
    }

    var body: some View {
        Group {
            if repository.books.isEmpty {
                StatusView(title: "书架为空", message: "在书籍详情页将书籍加入书架")
            } else if displayedBooks.isEmpty {
                StatusView(
                    title: filter == .updates ? "暂无更新书籍" : "没有符合筛选条件的书籍",
                    message: "可以切换书架筛选条件"
                )
            } else {
                List {
                    ForEach(displayedBooks) { book in
                        VStack(alignment: .leading, spacing: 10) {
                            HStack(alignment: .top, spacing: 12) {
                                CoverImage(urlString: book.coverURL, width: 56, height: 76)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(book.name).font(.headline)
                                    if book.hasUpdate {
                                        Text("\(book.updateCount) 章更新")
                                            .font(.caption.bold())
                                            .padding(.horizontal, 7).padding(.vertical, 3)
                                            .background(.blue.opacity(0.14), in: Capsule())
                                            .foregroundStyle(.blue)
                                    }
                                    Text(book.author).font(.subheadline).foregroundStyle(.secondary)
                                    if let latest = book.lastKnownLatestChapterName, !latest.isEmpty {
                                        Text("最新：\(latest)").font(.caption).lineLimit(1)
                                    }
                                    if let progress = book.progress {
                                        Text("当前：\(progress.lastChapterName)").font(.caption).lineLimit(1)
                                        if let overall = progress.overallProgress {
                                            ProgressView(value: overall)
                                                .accessibilityLabel("全书阅读进度")
                                            Text("阅读 \(overall.formatted(.percent.precision(.fractionLength(0))))")
                                                .font(.caption).foregroundStyle(.secondary)
                                        }
                                    } else {
                                        Text("未开始").font(.caption).foregroundStyle(.secondary)
                                    }
                                    if let lastReadAt = book.lastReadAt {
                                        Text(lastReadAt, style: .relative)
                                            .font(.caption2).foregroundStyle(.secondary)
                                    }
                                    if viewModel.checkingBookIDs.contains(book.id) {
                                        Label("检查更新中", systemImage: "arrow.triangle.2.circlepath")
                                            .font(.caption2).foregroundStyle(.secondary)
                                    } else if book.lastUpdateError != nil {
                                        Label("更新失败", systemImage: "exclamationmark.circle")
                                            .font(.caption2).foregroundStyle(.orange)
                                    } else if let checkedAt = book.lastCheckedAt {
                                        HStack(spacing: 3) {
                                            Text("检查于")
                                            Text(checkedAt, style: .relative)
                                        }
                                        .font(.caption2).foregroundStyle(.secondary)
                                    }
                                }
                            }
                            NavigationLink {
                                ContinueReadingView(book: book, dependencies: dependencies)
                            } label: {
                                Label(
                                    book.progress == nil ? "开始阅读" : "继续阅读",
                                    systemImage: "book.pages"
                                )
                                .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.borderedProminent)
                        }
                        .padding(.vertical, 5)
                        .contextMenu {
                            Button {
                                viewModel.refresh(book)
                            } label: { Label("检查更新", systemImage: "arrow.clockwise") }
                            .disabled(viewModel.checkingBookIDs.contains(book.id))
                            Button("删除", role: .destructive) { pendingDeletion = book }
                        }
                        .swipeActions(edge: .leading) {
                            Button { viewModel.refresh(book) } label: {
                                Label("检查更新", systemImage: "arrow.clockwise")
                            }
                            .tint(.blue)
                        }
                    }
                    .onDelete { offsets in
                        pendingDeletion = offsets.compactMap { displayedBooks[safe: $0] }.first
                    }
                }
                .refreshable { _ = await viewModel.refreshAll() }
            }
        }
        .navigationTitle("书架")
        .overlay(alignment: .bottom) {
            if let summary = viewModel.lastSummary {
                Button { showsUpdateSummary = true } label: {
                    Text("检查 \(summary.checkedCount) 本 · 更新 \(summary.updatedBookCount) 本 · 新增 \(summary.newChapterCount) 章 · 失败 \(summary.failed) 本")
                        .font(.caption).padding(8).background(.thinMaterial, in: Capsule()).padding()
                }
                .buttonStyle(.plain)
            }
        }
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button { showsUpdateSettings = true } label: {
                    Label("更新设置", systemImage: "gearshape")
                }
                Menu {
                    Picker("筛选", selection: $filter) {
                        ForEach(LibraryFilter.allCases) { value in Text(value.title).tag(value) }
                    }
                    Divider()
                    Picker("排序", selection: $sortPreference.mode) {
                        ForEach(LibrarySortMode.allCases) { mode in Text(mode.title).tag(mode) }
                    }
                } label: { Label("筛选与排序", systemImage: "line.3.horizontal.decrease.circle") }
            }
        }
        .sheet(isPresented: $showsUpdateSettings) {
            NavigationStack {
                LibraryUpdateSettingsView(
                    store: dependencies.libraryUpdateSettingsStore,
                    notifier: dependencies.libraryUpdateNotifier
                )
            }
        }
        .sheet(isPresented: $showsUpdateSummary) {
            NavigationStack {
                LibraryUpdateSummaryView(summary: viewModel.lastSummary ?? .empty)
            }
            .presentationDetents([.medium])
        }
        .confirmationDialog(
            "从书架删除《\(pendingDeletion?.name ?? "")》？",
            isPresented: Binding(get: { pendingDeletion != nil }, set: { if !$0 { pendingDeletion = nil } }),
            titleVisibility: .visible
        ) {
            Button("删除", role: .destructive) {
                if let book = pendingDeletion { dependencies.removeFromLibrary(book) }
                pendingDeletion = nil
            }
            Button("取消", role: .cancel) { pendingDeletion = nil }
        } message: {
            Text("阅读进度、章节缓存和书签将同时清除；书源不会被删除。")
        }
    }
}

private struct LibraryUpdateSummaryView: View {
    let summary: LibraryRefreshSummary
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        List {
            Section("更新结果") {
                LabeledContent("检查书籍", value: "\(summary.checkedCount) 本")
                LabeledContent("发现更新", value: "\(summary.updatedBookCount) 本")
                LabeledContent("新增章节", value: "\(summary.newChapterCount) 章")
                LabeledContent("失败", value: "\(summary.failed) 本")
            }
            if !summary.failures.isEmpty {
                Section("失败书目") {
                    ForEach(summary.failures) { failure in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(failure.bookName)
                            Text(failure.message).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .navigationTitle("检查更新")
        .toolbar {
            ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } }
        }
    }
}

private extension Collection {
    subscript(safe index: Index) -> Element? { indices.contains(index) ? self[index] : nil }
}

private struct ContinueReadingView: View {
    let book: LibraryBook
    let dependencies: AppDependencies
    @StateObject private var viewModel: TOCViewModel

    init(book: LibraryBook, dependencies: AppDependencies) {
        self.book = book
        self.dependencies = dependencies
        _viewModel = StateObject(wrappedValue: TOCViewModel(
            source: book.source, book: book.bookInfo, service: dependencies.tocService
        ))
    }

    var body: some View {
        Group {
            if viewModel.hasLoaded, !viewModel.chapters.isEmpty {
                ReaderView(
                    source: book.source,
                    book: book.bookInfo,
                    libraryBookID: book.id,
                    chapters: viewModel.chapters,
                    initialChapterIndex: initialIndex,
                    contentService: dependencies.contentService,
                    progressStore: dependencies.libraryRepository,
                    bookmarkStore: dependencies.bookmarkRepository,
                    settingsStore: dependencies.readerSettingsStore,
                    paginator: dependencies.readerPaginator
                )
            } else if viewModel.isLoading {
                ProgressView("正在恢复阅读…")
            } else if let message = viewModel.errorMessage {
                StatusView(title: "无法恢复阅读", message: message) { Task { await viewModel.retry() } }
            } else if viewModel.hasLoaded {
                StatusView(title: "目录为空", message: "该书源没有返回章节")
            }
        }
        .task { await viewModel.loadIfNeeded() }
    }

    private var initialIndex: Int {
        guard let progress = book.progress else { return 0 }
        if let exact = viewModel.chapters.firstIndex(where: { $0.url == progress.lastChapterURL }) {
            return exact
        }
        return min(max(progress.lastChapterIndex, 0), max(viewModel.chapters.count - 1, 0))
    }
}
