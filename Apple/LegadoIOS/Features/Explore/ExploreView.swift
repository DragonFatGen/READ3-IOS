import LegadoCore
import SwiftUI

struct ExploreView: View {
    @ObservedObject private var sourceStore: BookSourceStore
    @ObservedObject private var libraryRepository: LibraryRepository
    private let dependencies: AppDependencies
    @StateObject private var viewModel: ExploreViewModel

    init(dependencies: AppDependencies) {
        sourceStore = dependencies.sourceStore
        libraryRepository = dependencies.libraryRepository
        self.dependencies = dependencies
        _viewModel = StateObject(wrappedValue: ExploreViewModel(service: dependencies.exploreService))
    }

    private var availableSources: [BookSource] {
        sourceStore.enabledSources.filter { source in
            guard let value = source.exploreUrl else { return false }
            return !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    var body: some View {
        Group {
            if availableSources.isEmpty {
                StatusView(
                    title: "暂无可用发现书源",
                    message: "请导入并启用包含 exploreUrl 的书源"
                )
            } else {
                exploreContent
            }
        }
        .navigationTitle("发现")
        .toolbar {
            if viewModel.source != nil {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        viewModel.refreshCategories()
                    } label: {
                        Label("刷新分类", systemImage: "arrow.clockwise")
                    }
                    .disabled(viewModel.isLoadingCategories)
                    .accessibilityLabel("刷新发现分类")
                }
            }
        }
        .onAppear {
            viewModel.updateAvailableSources(availableSources)
        }
        .onChange(of: sourceStore.enabledSources) { _ in
            viewModel.updateAvailableSources(availableSources)
        }
    }

    private var exploreContent: some View {
        VStack(spacing: 0) {
            sourcePicker
            categoryContent
            Divider()
            resultContent
        }
    }

    private var sourcePicker: some View {
        Picker("发现书源", selection: Binding(
            get: { viewModel.source?.bookSourceUrl ?? availableSources.first?.bookSourceUrl ?? "" },
            set: { identity in
                viewModel.selectSource(availableSources.first { $0.bookSourceUrl == identity })
            }
        )) {
            ForEach(availableSources, id: \.bookSourceUrl) { source in
                Text(source.bookSourceName).tag(source.bookSourceUrl)
            }
        }
        .pickerStyle(.menu)
        .padding(.horizontal)
        .padding(.vertical, 8)
    }

    @ViewBuilder
    private var categoryContent: some View {
        if viewModel.isLoadingCategories {
            ProgressView("正在加载分类…")
                .frame(maxWidth: .infinity, minHeight: 80)
        } else if let message = viewModel.categoryErrorMessage {
            StatusView(title: "分类加载失败", message: message) {
                viewModel.refreshCategories()
            }
            .frame(minHeight: 140, maxHeight: 200)
        } else if viewModel.categories.isEmpty {
            Text("当前书源没有可用发现分类")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, minHeight: 80)
                .padding(.horizontal)
        } else {
            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(categoryGroups) { group in
                        if group.isStandalone, let index = group.indices.first {
                            categoryCell(at: index)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        } else {
                            LazyVGrid(
                                columns: [GridItem(.adaptive(minimum: 88), spacing: 8)],
                                alignment: .leading,
                                spacing: 8
                            ) {
                                ForEach(group.indices, id: \.self) { index in
                                    categoryCell(at: index)
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal)
                .padding(.bottom, 10)
            }
            .frame(maxHeight: 190)
        }
    }

    @ViewBuilder
    private func categoryCell(at index: Int) -> some View {
        let category = viewModel.categories[index]
        if let url = category.url, !url.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            Button {
                viewModel.selectCategory(at: index)
            } label: {
                Text(category.title)
                    .font(.subheadline)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .foregroundStyle(viewModel.selectedCategoryIndex == index ? Color.white : Color.primary)
                    .background(
                        viewModel.selectedCategoryIndex == index ? Color.accentColor : Color.secondary.opacity(0.12),
                        in: RoundedRectangle(cornerRadius: 8)
                    )
            }
            .buttonStyle(.plain)
        } else {
            Text(category.title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.vertical, 3)
        }
    }

    @ViewBuilder
    private var resultContent: some View {
        if viewModel.isLoading {
            StatusView(title: "正在加载…", message: nil)
                .overlay { ProgressView() }
        } else if let message = viewModel.errorMessage {
            StatusView(title: "发现加载失败", message: message) {
                viewModel.retryFirstPage()
            }
        } else if viewModel.currentPage > 0 && viewModel.results.isEmpty {
            StatusView(title: "暂无书籍", message: "当前分类没有返回结果")
        } else {
            List {
                ForEach(Array(viewModel.results.enumerated()), id: \.offset) { _, book in
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

                if viewModel.isLoadingMore {
                    HStack {
                        Spacer()
                        ProgressView()
                        Spacer()
                    }
                    .listRowSeparator(.hidden)
                } else if let message = viewModel.loadMoreErrorMessage {
                    Button {
                        viewModel.loadMore()
                    } label: {
                        VStack(spacing: 4) {
                            Text(message).font(.caption).foregroundStyle(.secondary)
                            Text("点击重试")
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .listRowSeparator(.hidden)
                } else if viewModel.hasMore && !viewModel.results.isEmpty {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .listRowSeparator(.hidden)
                        .onAppear {
                            viewModel.loadMore()
                        }
                }
            }
            .listStyle(.plain)
            .refreshable {
                await viewModel.refreshBooks()
            }
        }
    }

    private var categoryGroups: [CategoryGroup] {
        var groups: [CategoryGroup] = []
        var run: [Int] = []
        func flushRun() {
            guard !run.isEmpty else { return }
            groups.append(CategoryGroup(indices: run, isStandalone: false))
            run.removeAll(keepingCapacity: true)
        }

        for index in viewModel.categories.indices {
            let category = viewModel.categories[index]
            let isHeader = category.url?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true
            let startsNewLine = category.style?.layoutWrapBefore == true
            let fullWidth = (category.style?.layoutFlexBasisPercent ?? -1) >= 0.95
            if isHeader || startsNewLine || fullWidth {
                flushRun()
                groups.append(CategoryGroup(indices: [index], isStandalone: true))
            } else {
                run.append(index)
            }
        }
        flushRun()
        return groups
    }
}

private struct CategoryGroup: Identifiable {
    let indices: [Int]
    let isStandalone: Bool
    var id: Int { indices[0] }
}
