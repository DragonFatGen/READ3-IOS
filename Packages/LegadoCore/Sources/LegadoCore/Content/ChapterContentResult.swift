public struct ChapterContentResult: Sendable, Equatable {
    public let content: String
    public let chapterURL: String

    public init(content: String, chapterURL: String) {
        self.content = content
        self.chapterURL = chapterURL
    }
}
