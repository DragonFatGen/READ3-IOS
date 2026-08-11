public struct BookChapterResult: Sendable, Equatable {
    public let name: String
    public let url: String
    public let isVolume: Bool
    public let index: Int
    public let isVIP: Bool
    public let isPay: Bool
    public let tag: String
    public let bookURL: String
    public let sourceURL: String

    public init(
        name: String,
        url: String,
        isVolume: Bool,
        index: Int,
        isVIP: Bool = false,
        isPay: Bool = false,
        tag: String = "",
        bookURL: String,
        sourceURL: String
    ) {
        self.name = name
        self.url = url
        self.isVolume = isVolume
        self.index = index
        self.isVIP = isVIP
        self.isPay = isPay
        self.tag = tag
        self.bookURL = bookURL
        self.sourceURL = sourceURL
    }
}
