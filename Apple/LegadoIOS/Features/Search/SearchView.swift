import Foundation
import LegadoCore
import SwiftUI

struct SearchView: View {
    @ObservedObject private var sourceStore: BookSourceStore
    @ObservedObject private var libraryRepository: LibraryRepository
    let dependencies: AppDependencies
    @StateObject private var viewModel: SearchViewModel
    @State private var selectedIdentity: String?

    init(source: BookSource, dependencies: AppDependencies) {
        sourceStore = dependencies.sourceStore
        libraryRepository = dependencies.libraryRepository
        self.dependencies = dependencies
        _selectedIdentity = State(initialValue: source.bookSourceUrl)
        _viewModel = StateObject(wrappedValue: SearchViewModel(
            source: source,
            service: dependencies.searchService
        ))
    }

    var body: some View {
        Group {
            if sourceStore.enabledSources.isEmpty {
                StatusView(title: "暂无已启用书源", message: "请前往书源管理启用或导入书源")
            } else {
                searchContent
            }
        }
        .navigationTitle(viewModel.source?.bookSourceName ?? "搜索")
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: sourceStore.enabledSources) { sources in
            if let selectedIdentity,
               let refreshed = sources.first(where: { $0.bookSourceUrl == selectedIdentity }) {
                viewModel.selectSource(refreshed)
                return
            }
            select(identity: sources.first?.bookSourceUrl)
        }
        .onDisappear(perform: viewModel.cancelSearch)
    }

    private var searchContent: some View {
        VStack(spacing: 0) {
            Picker("搜索书源", selection: Binding(
                get: { selectedIdentity ?? sourceStore.enabledSources.first?.bookSourceUrl ?? "" },
                set: { select(identity: $0) }
            )) {
                ForEach(sourceStore.enabledSources, id: \.bookSourceUrl) { source in
                    Text(source.bookSourceName).tag(source.bookSourceUrl)
                }
            }
            .pickerStyle(.menu)
            .padding(.horizontal)

            HStack {
                TextField("输入书名或作者", text: $viewModel.query)
                    .textFieldStyle(.roundedBorder)
                    .submitLabel(.search)
                    .onSubmit(viewModel.search)
                Button("搜索", action: viewModel.search)
                    .disabled(viewModel.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding()

            if viewModel.isLoading {
                Spacer(); ProgressView("正在搜索…"); Spacer()
            } else if let errorMessage = viewModel.errorMessage {
                StatusView(title: "搜索失败", message: errorMessage, retry: viewModel.search)
            } else if viewModel.hasSearched && viewModel.results.isEmpty {
                StatusView(title: "没有搜索结果", message: "请尝试其他关键词")
            } else {
                List(Array(viewModel.results.enumerated()), id: \.offset) { _, book in
                    if let source = viewModel.source {
                        NavigationLink {
                            BookDetailView(source: source, searchResult: book, dependencies: dependencies)
                        } label: {
                            SearchResultRow(
                                book: book,
                                isInLibrary: libraryRepository.contains(
                                    sourceURL: source.bookSourceUrl,
                                    bookURL: book.bookURL
                                )
                            )
                        }
                    }
                }
                .listStyle(.plain)
            }
        }
    }

    private func select(identity: String?) {
        selectedIdentity = identity
        viewModel.selectSource(identity.flatMap(sourceStore.source(for:)))
    }
}

private struct SearchResultRow: View {
    let book: BookSearchResult
    let isInLibrary: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            CoverImage(urlString: book.coverURL, width: 56, height: 76)
            VStack(alignment: .leading, spacing: 5) {
                HStack {
                    Text(book.name).font(.headline)
                    if isInLibrary {
                        Text("已在书架")
                            .font(.caption2.bold())
                            .foregroundStyle(.blue)
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(.blue.opacity(0.12), in: Capsule())
                    }
                }
                Text(book.author).font(.subheadline).foregroundStyle(.secondary)
                if let lastChapter = book.lastChapter, !lastChapter.isEmpty {
                    Text(lastChapter).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
            }
        }
        .padding(.vertical, 4)
    }
}
