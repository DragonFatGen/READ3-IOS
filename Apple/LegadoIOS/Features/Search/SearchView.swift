import Foundation
import LegadoCore
import SwiftUI

struct SearchView: View {
    let source: BookSource
    let dependencies: AppDependencies
    @StateObject private var viewModel: SearchViewModel

    init(source: BookSource, dependencies: AppDependencies) {
        self.source = source
        self.dependencies = dependencies
        _viewModel = StateObject(wrappedValue: SearchViewModel(
            source: source,
            service: dependencies.searchService
        ))
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                TextField("输入书名或作者", text: $viewModel.query)
                    .textFieldStyle(.roundedBorder)
                    .submitLabel(.search)
                    .onSubmit(viewModel.search)
                Button(action: viewModel.search) {
                    Text("搜索")
                }
                .disabled(viewModel.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding()

            if viewModel.isLoading {
                Spacer()
                ProgressView("正在搜索…")
                Spacer()
            } else if let errorMessage = viewModel.errorMessage {
                StatusView(title: "搜索失败", message: errorMessage, retry: viewModel.search)
            } else if viewModel.hasSearched && viewModel.results.isEmpty {
                StatusView(title: "没有搜索结果", message: "请尝试其他关键词")
            } else {
                List(Array(viewModel.results.enumerated()), id: \.offset) { _, book in
                    NavigationLink {
                        BookDetailView(
                            source: source,
                            searchResult: book,
                            dependencies: dependencies
                        )
                    } label: {
                        SearchResultRow(book: book)
                    }
                }
                .listStyle(.plain)
            }
        }
        .navigationTitle(source.bookSourceName)
        .navigationBarTitleDisplayMode(.inline)
        .onDisappear(perform: viewModel.cancelSearch)
    }
}

private struct SearchResultRow: View {
    let book: BookSearchResult

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            CoverImage(urlString: book.coverURL, width: 56, height: 76)
            VStack(alignment: .leading, spacing: 5) {
                Text(book.name).font(.headline)
                Text(book.author).font(.subheadline).foregroundStyle(.secondary)
                if let lastChapter = book.lastChapter, !lastChapter.isEmpty {
                    Text(lastChapter).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
            }
        }
        .padding(.vertical, 4)
    }
}
