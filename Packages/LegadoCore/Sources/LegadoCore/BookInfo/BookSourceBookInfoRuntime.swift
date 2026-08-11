import Foundation

public struct BookSourceBookInfoRuntime: Sendable {
    private let httpClient: any HTTPClient
    private let requestBuilder: RequestBuilder
    private let selectorExecutor: any RuleNodeSelectorExecutor
    private let javaScriptExecutor: (any RuleJavaScriptExecutor)?
    private let textDecoder: any TextDecoder
    private let parser = RuleParser()
    private let urlResolver = URLResolver()

    public init(
        httpClient: any HTTPClient,
        requestBuilder: RequestBuilder = RequestBuilder(),
        selectorExecutor: any RuleNodeSelectorExecutor = LegadoRuleSelectorExecutor(),
        javaScriptExecutor: (any RuleJavaScriptExecutor)? = nil,
        textDecoder: any TextDecoder = FoundationTextDecoder()
    ) {
        self.httpClient = httpClient
        self.requestBuilder = requestBuilder
        self.selectorExecutor = selectorExecutor
        self.javaScriptExecutor = javaScriptExecutor
        self.textDecoder = textDecoder
    }

    public func fetchBookInfo(
        source: BookSource,
        book: BookSearchResult
    ) async throws -> BookInfoResult {
        let rules = source.ruleBookInfo ?? BookInfoRule()
        if requiresNetworkHost(book.bookURL) {
            throw BookInfoError.unsupportedJavaScriptNetworkHost
        }

        // Search has already completed the detail URL. Preserve its Legado option
        // suffix verbatim; RequestBuilder owns resolution of the request target.
        let canonicalBookURL = book.bookURL
        let request: HTTPRequest
        do {
            request = try await requestBuilder.build(
                canonicalBookURL,
                source: source,
                context: RequestBuildContext(
                    sourceURL: source.bookSourceUrl,
                    baseURL: source.bookSourceUrl,
                    sourceIdentifier: source.bookSourceUrl
                )
            )
        } catch {
            throw BookInfoError.requestBuildFailed(error.localizedDescription)
        }

        let response: HTTPResponse
        do { response = try await httpClient.send(request) }
        catch { throw BookInfoError.networkFailed(error.localizedDescription) }

        let body: String
        do { body = try response.text(decoder: textDecoder) }
        catch { throw BookInfoError.responseDecodeFailed(error.localizedDescription) }

        var context = RuleExecutionContext(
            baseUrl: canonicalBookURL,
            javaScriptSource: JavaScriptSourceSnapshot(
                identifier: source.bookSourceUrl,
                url: source.bookSourceUrl,
                header: source.header
            )
        )
        let nodeExecutor = RuleNodeExecutor(
            selectorExecutor: selectorExecutor,
            javaScriptExecutor: javaScriptExecutor
        )
        let responseIsJSON = Self.looksLikeJSON(body)
        let responseInput = RuleExecutionInput(.string(body))
        var fieldInput: RuleExecutionInput
        do {
            fieldInput = try nodeExecutor.makeRootContext(
                input: responseInput,
                contentIsJSON: responseIsJSON,
                context: &context
            )
        } catch {
            throw BookInfoError.initRuleFailed(error.localizedDescription)
        }

        let hasInitRule = nonblank(rules.`init`) != nil
        if let initRule = nonblank(rules.`init`) {
            if requiresNetworkHost(initRule) {
                throw BookInfoError.unsupportedJavaScriptNetworkHost
            }
            do {
                let expression = try parser.parse(
                    initRule,
                    context: RuleParseContext(contentIsJSON: responseIsJSON)
                )
                fieldInput = try nodeExecutor.executeContext(
                    expression,
                    // Android init starts with the response String. Node-producing
                    // selector stages parse it once and retain their selected graph;
                    // a leading pure-JavaScript stage must still receive the String.
                    input: responseInput,
                    context: &context
                )
                if !fieldInput.hasStructuredValue {
                    fieldInput = try nodeExecutor.makeRootContext(
                        input: fieldInput,
                        contentIsJSON: Self.looksLikeJSON(fieldInput.value.stringValue),
                        context: &context
                    )
                }
            } catch let error as RuleExecutionError {
                if case .unsupportedExecutionNode = error {
                    throw BookInfoError.unsupportedStructuredRule(initRule)
                }
                throw BookInfoError.initRuleFailed(error.localizedDescription)
            } catch let error as BookInfoError {
                throw error
            } catch {
                throw BookInfoError.initRuleFailed(error.localizedDescription)
            }
        }

        let allowsRename = nonblank(rules.canReName) != nil
        let responseStringInput = hasInitRule ? nil : responseInput
        var name = book.name
        let parsedName = formatName(try requiredField(
            "name", rule: rules.name, input: fieldInput,
            responseStringInput: responseStringInput, context: &context
        ))
        if !parsedName.isEmpty, allowsRename || name.isEmpty { name = parsedName }

        var author = book.author
        let parsedAuthor = formatAuthor(try requiredField(
            "author", rule: rules.author, input: fieldInput,
            responseStringInput: responseStringInput, context: &context
        ))
        if !parsedAuthor.isEmpty, allowsRename || author.isEmpty { author = parsedAuthor }

        let kind = try optionalField(
            "kind", rule: rules.kind, input: fieldInput,
            responseStringInput: responseStringInput, context: &context, join: ","
        ).flatMap(nonblank) ?? book.kind
        let wordCount = formatWordCount(try optionalField(
            "wordCount", rule: rules.wordCount, input: fieldInput,
            responseStringInput: responseStringInput, context: &context
        )).flatMap(nonblank) ?? book.wordCount
        let lastChapter = try optionalField(
            "lastChapter", rule: rules.lastChapter, input: fieldInput,
            responseStringInput: responseStringInput, context: &context
        ).flatMap(nonblank) ?? book.lastChapter
        let intro = formatIntro(try optionalField(
            "intro", rule: rules.intro, input: fieldInput,
            responseStringInput: responseStringInput, context: &context
        )).flatMap(nonblank) ?? book.intro
        let coverRaw = try optionalField(
            "coverUrl", rule: rules.coverUrl, input: fieldInput,
            responseStringInput: responseStringInput, context: &context
        )
        let coverURL = coverRaw.flatMap(nonblank)
            .map { urlResolver.resolve($0, against: response.finalURL.absoluteString) }
            ?? book.coverURL

        let tocRaw = try requiredField(
            "tocUrl", rule: rules.tocUrl, input: fieldInput,
            responseStringInput: responseStringInput, context: &context
        )
        let tocURL = nonblank(tocRaw).map {
            urlResolver.resolve($0, against: response.finalURL.absoluteString)
        } ?? canonicalBookURL

        return BookInfoResult(
            name: name,
            author: author,
            bookURL: canonicalBookURL,
            coverURL: coverURL,
            intro: intro,
            kind: kind,
            wordCount: wordCount,
            lastChapter: lastChapter,
            tocURL: tocURL,
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
        responseStringInput: RuleExecutionInput?,
        context: inout RuleExecutionContext
    ) throws -> String {
        guard let rule = nonblank(rule) else { return "" }
        if requiresNetworkHost(rule) { throw BookInfoError.unsupportedJavaScriptNetworkHost }
        do {
            return try executeField(
                rule, input: input, responseStringInput: responseStringInput, context: &context
            ).stringValue
        }
        catch let error as BookInfoError { throw error }
        catch { throw BookInfoError.fieldRuleFailed(field: field, message: error.localizedDescription) }
    }

    private func optionalField(
        _ field: String,
        rule: String?,
        input: RuleExecutionInput,
        responseStringInput: RuleExecutionInput?,
        context: inout RuleExecutionContext,
        join: String = "\n"
    ) throws -> String? {
        guard let rule = nonblank(rule) else { return nil }
        if requiresNetworkHost(rule) { throw BookInfoError.unsupportedJavaScriptNetworkHost }
        do {
            return try executeField(
                rule, input: input, responseStringInput: responseStringInput, context: &context
            )
                .stringValues.joined(separator: join)
        } catch let error as BookInfoError {
            throw error
        } catch {
            // Android isolates these optional fields and retains the search value.
            _ = field
            return nil
        }
    }

    private func executeField(
        _ rule: String,
        input: RuleExecutionInput,
        responseStringInput: RuleExecutionInput?,
        context: inout RuleExecutionContext
    ) throws -> RuleValue {
        context.currentResult = .none
        context.captureGroups = []
        let contentIsJSON = input.node?.kind == .json ||
            input.nodes?.nodes.first?.kind == .json
        let expression = try parser.parse(rule, context: RuleParseContext(contentIsJSON: contentIsJSON))
        let executionInput = if case .javaScript = expression {
            responseStringInput ?? input
        } else {
            input
        }
        return try RuleExecutor(
            selectorExecutor: selectorExecutor,
            javaScriptExecutor: javaScriptExecutor
        ).execute(expression, input: executionInput, context: &context).value
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
