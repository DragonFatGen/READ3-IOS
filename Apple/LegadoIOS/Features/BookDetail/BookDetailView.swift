import Foundation
import LegadoCore
import SwiftUI

struct BookDetailView: View {
    let source: BookSource
    let dependencies: AppDependencies
    @ObservedObject private var libraryRepository: LibraryRepository
    @StateObject private var viewModel: BookDetailViewModel
    @State private var reloadID = 0

    init(source: BookSource, searchResult: BookSearchResult, dependencies: AppDependencies) {
        self.source = source
        self.dependencies = dependencies
        _libraryRepository = ObservedObject(wrappedValue: dependencies.libraryRepository)
        _viewModel = StateObject(wrappedValue: BookDetailViewModel(
            source: source,
            searchResult: searchResult,
            service: dependencies.bookInfoService
        ))
    }

    var body: some View {
        Group {
            if let info = viewModel.bookInfo {
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        HStack(alignment: .top, spacing: 16) {
                            CoverImage(urlString: info.coverURL, width: 96, height: 132)
                            VStack(alignment: .leading, spacing: 8) {
                                Text(info.name).font(.title2.bold())
                                Text(info.author).foregroundStyle(.secondary)
                                metadata(info.kind)
                                metadata(info.wordCount)
                                metadata(info.lastChapter)
                            }
                        }
                        if let intro = info.intro, !intro.isEmpty {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("简介").font(.headline)
                                Text(intro).textSelection(.enabled)
                            }
                        }
                        VStack(alignment: .leading, spacing: 8) {
                            Text("来源").font(.headline)
                            Text(info.sourceName).foregroundStyle(.secondary)
                            HStack(spacing: 16) {
                                if let bookURL = URL(string: info.bookURL) {
                                    Link("书籍页面", destination: bookURL)
                                }
                                if let tocURL = URL(string: info.tocURL) {
                                    Link("目录页面", destination: tocURL)
                                }
                            }
                            .font(.footnote)
                        }
                        NavigationLink {
                            TOCView(source: source, bookInfo: info, dependencies: dependencies)
                        } label: {
                            Label("查看目录", systemImage: "list.bullet")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        Button {
                            libraryRepository.add(source: source, bookInfo: info)
                        } label: {
                            Label(
                                libraryRepository.contains(
                                    sourceURL: source.bookSourceUrl,
                                    bookURL: info.bookURL
                                ) ? "已在书架" : "加入书架",
                                systemImage: "books.vertical"
                            )
                            .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                    }
                    .padding()
                }
            } else if viewModel.isLoading {
                ProgressView("正在加载书籍详情…")
            } else if let errorMessage = viewModel.errorMessage {
                StatusView(title: "详情加载失败", message: errorMessage) {
                    reloadID += 1
                }
            }
        }
        .navigationTitle(viewModel.bookInfo?.name ?? viewModel.searchResult.name)
        .navigationBarTitleDisplayMode(.inline)
        .task(id: reloadID) {
            if reloadID == 0 {
                await viewModel.loadIfNeeded()
            } else {
                await viewModel.retry()
            }
        }
    }

    @ViewBuilder
    private func metadata(_ value: String?) -> some View {
        if let value, !value.isEmpty {
            Text(value).font(.caption).foregroundStyle(.secondary).lineLimit(2)
        }
    }
}
