import SwiftUI

struct BookshelfView: View {
    @ObservedObject var repository: LibraryRepository
    let dependencies: AppDependencies

    var body: some View {
        Group {
            if repository.books.isEmpty {
                StatusView(title: "书架为空", message: "在书籍详情页将书籍加入书架")
            } else {
                List {
                    ForEach(repository.books) { book in
                        VStack(alignment: .leading, spacing: 10) {
                            HStack(alignment: .top, spacing: 12) {
                                CoverImage(urlString: book.coverURL, width: 56, height: 76)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(book.name).font(.headline)
                                    Text(book.author).font(.subheadline).foregroundStyle(.secondary)
                                    if let progress = book.progress {
                                        Text(progress.lastChapterName).font(.caption).lineLimit(1)
                                        if let overall = progress.overallProgress {
                                            ProgressView(value: overall)
                                                .accessibilityLabel("全书阅读进度")
                                        }
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
                    }
                    .onDelete { offsets in
                        let books = offsets.compactMap { repository.books[safe: $0] }
                        books.forEach { dependencies.removeFromLibrary($0) }
                    }
                }
            }
        }
        .navigationTitle("书架")
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
