import LegadoCore
import SwiftUI

struct TOCView: View {
    let source: BookSource
    let bookInfo: BookInfoResult
    let dependencies: AppDependencies
    @StateObject private var viewModel: TOCViewModel
    @State private var reloadID = 0

    init(source: BookSource, bookInfo: BookInfoResult, dependencies: AppDependencies) {
        self.source = source
        self.bookInfo = bookInfo
        self.dependencies = dependencies
        _viewModel = StateObject(wrappedValue: TOCViewModel(
            source: source,
            book: bookInfo,
            service: dependencies.tocService
        ))
    }

    var body: some View {
        Group {
            if viewModel.isLoading {
                ProgressView("正在加载目录…")
            } else if let errorMessage = viewModel.errorMessage {
                StatusView(title: "目录加载失败", message: errorMessage) {
                    reloadID += 1
                }
            } else if viewModel.hasLoaded && viewModel.chapters.isEmpty {
                StatusView(title: "目录为空", message: "该书源没有返回章节") {
                    reloadID += 1
                }
            } else {
                List(Array(viewModel.chapters.enumerated()), id: \.offset) { _, chapter in
                    if chapter.isVolume {
                        ChapterRow(chapter: chapter)
                    } else {
                        NavigationLink {
                            ReaderView(
                                source: source,
                                book: bookInfo,
                                libraryBookID: LibraryBook.identifier(
                                    sourceURL: source.bookSourceUrl,
                                    bookURL: bookInfo.bookURL
                                ),
                                chapters: viewModel.chapters,
                                initialChapterIndex: viewModel.chapters.firstIndex(where: {
                                    $0.url == chapter.url
                                }) ?? 0,
                                contentService: dependencies.contentService,
                                progressStore: dependencies.libraryRepository,
                                settingsStore: dependencies.readerSettingsStore
                            )
                        } label: {
                            ChapterRow(chapter: chapter)
                        }
                    }
                }
                .listStyle(.plain)
            }
        }
        .navigationTitle("章节目录")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: reloadID) {
            if reloadID == 0 {
                await viewModel.loadIfNeeded()
            } else {
                await viewModel.retry()
            }
        }
    }
}

private struct ChapterRow: View {
    let chapter: BookChapterResult

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text(chapter.name)
                    .font(chapter.isVolume ? .headline : .body)
                if !chapter.tag.isEmpty {
                    Text(chapter.tag).font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
            if chapter.isVIP || chapter.isPay {
                Image(systemName: "lock.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("付费章节")
            }
        }
    }
}
