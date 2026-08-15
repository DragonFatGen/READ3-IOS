import SwiftUI

struct ReaderBookmarksSheet: View {
    let bookmarks: [ReaderBookmark]
    let onSelect: (ReaderBookmark) -> Void
    let onDelete: (UUID) -> Void

    var body: some View {
        NavigationStack {
            Group {
                if bookmarks.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "bookmark").font(.largeTitle)
                        Text("暂无书签").font(.headline)
                        Text("在阅读器顶部点击书签按钮即可添加")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List {
                        ForEach(bookmarks) { bookmark in
                            Button { onSelect(bookmark) } label: {
                                VStack(alignment: .leading, spacing: 6) {
                                    HStack {
                                        Text(bookmark.chapterName).font(.headline).lineLimit(1)
                                        Spacer()
                                        Text(bookmark.chapterProgress, format: .percent.precision(.fractionLength(0)))
                                            .font(.caption.monospacedDigit())
                                    }
                                    if !bookmark.previewText.isEmpty {
                                        Text(bookmark.previewText)
                                            .font(.subheadline)
                                            .foregroundStyle(.secondary)
                                            .lineLimit(3)
                                    }
                                    Text(bookmark.createdAt, format: .dateTime.year().month().day().hour().minute())
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .buttonStyle(.plain)
                        }
                        .onDelete { offsets in
                            offsets.compactMap { bookmarks[safe: $0]?.id }.forEach(onDelete)
                        }
                    }
                }
            }
            .navigationTitle("书签")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

private extension Collection {
    subscript(safe index: Index) -> Element? { indices.contains(index) ? self[index] : nil }
}
