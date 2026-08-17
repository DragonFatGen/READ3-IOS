import Foundation

enum BookListParseError: Error, Equatable {
    case bookListRuleFailed(String)
    case fieldRuleFailed(field: String, message: String)
    case unsupportedStructuredRule(String)
    case unsupportedJavaScriptNetworkHost
}

struct BookListParser: Sendable {
    private let selectorExecutor: any RuleNodeSelectorExecutor
    private let javaScriptExecutor: (any RuleJavaScriptExecutor)?
    private let parser = RuleParser()
    private let urlResolver = URLResolver()

    init(
        selectorExecutor: any RuleNodeSelectorExecutor,
        javaScriptExecutor: (any RuleJavaScriptExecutor)?
    ) {
        self.selectorExecutor = selectorExecutor
        self.javaScriptExecutor = javaScriptExecutor
    }

    func parse(
        body: String,
        rules: any BookListRuleDefinition,
        source: BookSource,
        baseURL: String,
        variables: [String: String] = [:]
    ) throws -> [BookSearchResult] {
        guard var listRule = nonblank(rules.bookList) else { return [] }
        let reverse = listRule.hasPrefix("-")
        if reverse || listRule.hasPrefix("+") { listRule.removeFirst() }
        if requiresNetworkHost(listRule) { throw BookListParseError.unsupportedJavaScriptNetworkHost }

        let expression: RuleExpression
        do {
            expression = try parser.parse(
                listRule,
                context: RuleParseContext(contentIsJSON: Self.looksLikeJSON(body))
            )
        } catch {
            throw BookListParseError.bookListRuleFailed(error.localizedDescription)
        }

        var context = makeContext(source: source, baseURL: baseURL, variables: variables)
        let collection: RuleNodeCollection
        do {
            collection = try RuleNodeExecutor(
                selectorExecutor: selectorExecutor,
                javaScriptExecutor: javaScriptExecutor
            ).execute(
                expression,
                input: RuleExecutionInput(.string(body)),
                context: &context
            )
        } catch let error as RuleExecutionError {
            if case .unsupportedExecutionNode = error {
                throw BookListParseError.unsupportedStructuredRule(listRule)
            }
            throw BookListParseError.bookListRuleFailed(error.localizedDescription)
        } catch {
            throw BookListParseError.bookListRuleFailed(error.localizedDescription)
        }

        let nodes = reverse ? Array(collection.nodes.reversed()) : collection.nodes
        return try nodes.compactMap {
            try parseItem(
                $0,
                rules: rules,
                source: source,
                baseURL: baseURL,
                variables: variables
            )
        }
    }

    private func parseItem(
        _ node: RuleNode,
        rules: any BookListRuleDefinition,
        source: BookSource,
        baseURL: String,
        variables: [String: String]
    ) throws -> BookSearchResult? {
        var context = makeContext(source: source, baseURL: baseURL, variables: variables)
        let input = RuleExecutionInput(node: node)

        let name = formatName(try requiredField("name", rule: rules.name, input: input, context: &context))
        guard !name.isEmpty else { return nil }
        let author = formatAuthor(try requiredField("author", rule: rules.author, input: input, context: &context))
        let kind = try optionalField("kind", rule: rules.kind, input: input, context: &context, join: ",")
        let wordCount = formatWordCount(try optionalField(
            "wordCount", rule: rules.wordCount, input: input, context: &context
        ))
        let lastChapter = try optionalField(
            "lastChapter", rule: rules.lastChapter, input: input, context: &context
        )
        let intro = formatIntro(try optionalField("intro", rule: rules.intro, input: input, context: &context))
        let coverRaw = try optionalField("coverUrl", rule: rules.coverUrl, input: input, context: &context)
        let coverURL = nonblank(coverRaw).map { urlResolver.resolve($0, against: baseURL) }
        let rawBookURL = try requiredField("bookUrl", rule: rules.bookUrl, input: input, context: &context)
        let bookURL = urlResolver.resolve(rawBookURL, against: baseURL)

        return BookSearchResult(
            name: name,
            author: author,
            bookURL: bookURL,
            coverURL: coverURL,
            intro: nonblank(intro),
            kind: nonblank(kind),
            wordCount: nonblank(wordCount),
            lastChapter: nonblank(lastChapter),
            sourceURL: source.bookSourceUrl,
            sourceName: source.bookSourceName,
            sourceType: source.bookSourceType,
            sourceOrder: source.customOrder
        )
    }

    private func requiredField(
        _ field: String,
        rule: String?,
        input: RuleExecutionInput,
        context: inout RuleExecutionContext
    ) throws -> String {
        guard let rule = nonblank(rule) else { return "" }
        if requiresNetworkHost(rule) { throw BookListParseError.unsupportedJavaScriptNetworkHost }
        do { return try executeField(rule, input: input, context: &context).stringValue }
        catch let error as BookListParseError { throw error }
        catch {
            throw BookListParseError.fieldRuleFailed(field: field, message: error.localizedDescription)
        }
    }

    private func optionalField(
        _ field: String,
        rule: String?,
        input: RuleExecutionInput,
        context: inout RuleExecutionContext,
        join: String = "\n"
    ) throws -> String? {
        guard let rule = nonblank(rule) else { return nil }
        if requiresNetworkHost(rule) { throw BookListParseError.unsupportedJavaScriptNetworkHost }
        do {
            return try executeField(rule, input: input, context: &context)
                .stringValues.joined(separator: join)
        } catch let error as BookListParseError {
            throw error
        } catch {
            return nil
        }
    }

    private func executeField(
        _ rule: String,
        input: RuleExecutionInput,
        context: inout RuleExecutionContext
    ) throws -> RuleValue {
        context.currentResult = .none
        context.captureGroups = []
        let expression = try parser.parse(
            rule,
            context: RuleParseContext(contentIsJSON: input.node?.kind == .json)
        )
        return try RuleExecutor(
            selectorExecutor: selectorExecutor,
            javaScriptExecutor: javaScriptExecutor
        ).execute(expression, input: input, context: &context).value
    }

    private func makeContext(
        source: BookSource,
        baseURL: String,
        variables: [String: String]
    ) -> RuleExecutionContext {
        RuleExecutionContext(
            baseUrl: baseURL,
            javaScriptSource: JavaScriptSourceSnapshot(
                identifier: source.bookSourceUrl,
                url: source.bookSourceUrl,
                header: source.header
            ),
            temporaryVariables: variables
        )
    }

    private func requiresNetworkHost(_ rule: String) -> Bool {
        let value = rule.lowercased()
        return ["java.ajax", "java.get", "java.post", "java.head"].contains { value.contains($0) }
    }

    private func nonblank(_ value: String?) -> String? {
        guard let value, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return value
    }

    private static func looksLikeJSON(_ value: String) -> Bool {
        guard let first = value.first(where: { !$0.isWhitespace }) else { return false }
        return first == "{" || first == "["
    }

    private func formatName(_ value: String) -> String {
        value.replacingOccurrences(
            of: #"\s+作\s*者.*|\s+\S+\s+著"#,
            with: "",
            options: .regularExpression
        ).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func formatAuthor(_ value: String) -> String {
        value.replacingOccurrences(
            of: #"^\s*作\s*者[:：\s]+|\s+著"#,
            with: "",
            options: .regularExpression
        ).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func formatWordCount(_ value: String?) -> String? {
        guard let value = nonblank(value) else { return nil }
        guard let count = Int(value), count > 0 else { return value }
        if count > 10_000 {
            let number = Double(count) / 10_000
            return String(
                format: number.rounded() == number ? "%.0f万字" : "%.1f万字",
                locale: Locale(identifier: "en_US_POSIX"),
                number
            )
        }
        return "\(count)字"
    }

    private func formatIntro(_ value: String?) -> String? {
        guard let value else { return nil }
        return value
            .replacingOccurrences(of: #"<[^>]+>"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
