import Foundation

struct ReaderBookmark: Identifiable, Codable, Equatable {
    let id: UUID
    let bookID: String
    let sourceIdentity: String
    let bookIdentity: String
    let chapterIndex: Int
    let chapterURL: String
    let chapterName: String
    let chapterProgress: Double
    let previewText: String
    let createdAt: Date
}

enum ReaderBookmarkMetrics {
    static let positionTolerance = 0.01
    static let previewCharacterLimit = 80
}

enum BookmarkPreviewBuilder {
    static func makePreview(
        content: String,
        normalizedProgress: Double,
        characterLimit: Int = ReaderBookmarkMetrics.previewCharacterLimit
    ) -> String {
        guard characterLimit > 0 else { return "" }
        let normalized = content
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
        guard !normalized.isEmpty else { return "" }

        let characters = Array(normalized)
        let progress = min(max(normalizedProgress, 0), 1)
        let center = Int((Double(max(characters.count - 1, 0)) * progress).rounded())
        let start = min(max(center - characterLimit / 3, 0), max(characters.count - characterLimit, 0))
        let end = min(start + characterLimit, characters.count)
        var preview = String(characters[start..<end])
        if start > 0 { preview = "…" + preview }
        if end < characters.count { preview += "…" }
        return preview
    }
}
