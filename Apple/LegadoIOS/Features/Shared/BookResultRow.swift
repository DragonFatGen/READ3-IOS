import LegadoCore
import SwiftUI

struct BookResultRow: View {
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
