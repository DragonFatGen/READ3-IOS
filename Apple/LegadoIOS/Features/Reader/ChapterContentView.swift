import LegadoCore
import SwiftUI

struct ChapterContentView: View {
    @StateObject private var viewModel: ChapterContentViewModel
    @State private var reloadID = 0

    init(
        source: BookSource,
        bookInfo: BookInfoResult,
        chapter: BookChapterResult,
        service: any ChapterContentLoading
    ) {
        _viewModel = StateObject(wrappedValue: ChapterContentViewModel(
            source: source,
            book: bookInfo,
            chapter: chapter,
            service: service
        ))
    }

    var body: some View {
        Group {
            if let result = viewModel.content {
                ScrollView {
                    Text(result.content)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                        .textSelection(.enabled)
                }
            } else if viewModel.isLoading {
                ProgressView("正在加载正文…")
            } else if let errorMessage = viewModel.errorMessage {
                StatusView(title: "正文加载失败", message: errorMessage) {
                    reloadID += 1
                }
            }
        }
        .navigationTitle(viewModel.chapter.name)
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
