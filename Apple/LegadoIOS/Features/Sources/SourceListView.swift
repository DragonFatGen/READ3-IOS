import LegadoCore
import SwiftUI
import UniformTypeIdentifiers

struct SourceListView: View {
    @ObservedObject var sourceStore: BookSourceStore
    let dependencies: AppDependencies
    @State private var isImporting = false

    var body: some View {
        Group {
            if sourceStore.sources.isEmpty {
                StatusView(
                    title: "尚未导入书源",
                    message: "导入 Legado 书源 JSON 后开始搜索"
                )
            } else {
                List(sourceStore.sources, id: \.bookSourceUrl) { source in
                    NavigationLink {
                        SearchView(source: source, dependencies: dependencies)
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(source.bookSourceName)
                            Text(source.bookSourceUrl)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                }
            }
        }
        .navigationTitle("书源")
        .toolbar {
            Button {
                isImporting = true
            } label: {
                Label("导入", systemImage: "square.and.arrow.down")
            }
        }
        .fileImporter(isPresented: $isImporting, allowedContentTypes: [.json]) { result in
            do {
                let url = try result.get()
                let hasAccess = url.startAccessingSecurityScopedResource()
                defer { if hasAccess { url.stopAccessingSecurityScopedResource() } }
                sourceStore.importSources(from: try Data(contentsOf: url))
            } catch {
                sourceStore.errorMessage = UserFacingError.message(
                    for: error,
                    fallback: "无法读取书源文件"
                )
            }
        }
        .alert("导入失败", isPresented: Binding(
            get: { sourceStore.errorMessage != nil },
            set: { if !$0 { sourceStore.errorMessage = nil } }
        )) {
            Button("好", role: .cancel) {}
        } message: {
            Text(sourceStore.errorMessage ?? "无法导入书源")
        }
    }
}
