protocol BookListRuleDefinition: Sendable {
    var bookList: String? { get }
    var name: String? { get }
    var author: String? { get }
    var intro: String? { get }
    var kind: String? { get }
    var lastChapter: String? { get }
    var updateTime: String? { get }
    var bookUrl: String? { get }
    var coverUrl: String? { get }
    var wordCount: String? { get }
}

extension SearchRule: BookListRuleDefinition {}
extension ExploreRule: BookListRuleDefinition {}
