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
        .onDisappear {
            viewModel.cancelSearch()
        }
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
                    .onSubmit {
                        viewModel.search()
                    }
                Button("搜索") {
                    viewModel.search()
                }
                    .disabled(viewModel.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding()

            if viewModel.isLoading {
                Spacer(); ProgressView("正在搜索…"); Spacer()
            } else if let errorMessage = viewModel.errorMessage {
                StatusView(title: "搜索失败", message: errorMessage) {
                    viewModel.search()
                }
            } else if viewModel.hasSearched && viewModel.results.isEmpty {
                StatusView(title: "没有搜索结果", message: "请尝试其他关键词")
            } else {
                List(Array(viewModel.results.enumerated()), id: \.offset) { _, book in
                    if let source = viewModel.source {
                        NavigationLink {
                            BookDetailView(source: source, searchResult: book, dependencies: dependencies)
                        } label: {
                            BookResultRow(
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
