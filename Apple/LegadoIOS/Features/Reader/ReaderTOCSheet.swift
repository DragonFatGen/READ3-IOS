import LegadoCore
import SwiftUI

struct ReaderTOCSheet: View {
    @Environment(\.dismiss) private var dismiss
    let chapters: [BookChapterResult]
    let currentIndex: Int
    let select: (Int) -> Void

    var body: some View {
        NavigationStack {
            List(Array(chapters.enumerated()), id: \.offset) { index, chapter in
                if chapter.isVolume {
                    Text(chapter.name).font(.headline)
                } else {
                    Button { select(index) } label: {
                        HStack {
                            Text(chapter.name).foregroundStyle(.primary)
                            Spacer()
                            if index == currentIndex {
                                Image(systemName: "checkmark.circle.fill")
                                    .accessibilityLabel("当前章节")
                            }
                        }
                    }
                }
            }
            .navigationTitle("章节目录")
            .toolbar {
                Button("完成") { dismiss() }
            }
        }
    }
}
