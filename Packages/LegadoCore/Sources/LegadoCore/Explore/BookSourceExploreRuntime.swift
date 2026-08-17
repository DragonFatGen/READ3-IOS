import Foundation

public struct BookSourceExploreRuntime: Sendable {
    private let httpClient: any HTTPClient
    private let requestBuilder: RequestBuilder
    private let bookListParser: BookListParser
    private let textDecoder: any TextDecoder
    private let hasJavaScriptExecutor: Bool

    public init(
        httpClient: any HTTPClient,
        requestBuilder: RequestBuilder? = nil,
        selectorExecutor: any RuleNodeSelectorExecutor = LegadoRuleSelectorExecutor(),
        javaScriptExecutor: (any RuleJavaScriptExecutor)? = nil,
        textDecoder: any TextDecoder = FoundationTextDecoder()
    ) {
        self.httpClient = httpClient
        self.requestBuilder = requestBuilder ?? RequestBuilder(javaScriptExecutor: javaScriptExecutor)
        bookListParser = BookListParser(
            selectorExecutor: selectorExecutor,
            javaScriptExecutor: javaScriptExecutor
        )
        self.textDecoder = textDecoder
        hasJavaScriptExecutor = javaScriptExecutor != nil
    }

    public func explore(
        source: BookSource,
        url: String,
        page: Int = 1
    ) async throws -> [BookSearchResult] {
        guard nonblank(url) != nil else { throw BookExploreError.exploreNotSupported }
        let rules: any BookListRuleDefinition
        if let exploreRules = source.ruleExplore, nonblank(exploreRules.bookList) != nil {
            rules = exploreRules
        } else if let searchRules = source.ruleSearch, nonblank(searchRules.bookList) != nil {
            rules = searchRules
        } else {
            throw BookExploreError.exploreNotSupported
        }
        if requiresNetworkHost(url) { throw BookExploreError.unsupportedJavaScriptNetworkHost }
        if nonblank(source.loginCheckJs) != nil { throw BookExploreError.unsupportedWebView }

        let built: RequestBuildResult
        do {
            built = try await requestBuilder.buildResult(
                url,
                source: source,
                context: RequestBuildContext(
                    page: page,
                    sourceURL: source.bookSourceUrl,
                    baseURL: source.bookSourceUrl,
                    sourceIdentifier: source.bookSourceUrl
                )
            )
        } catch {
            throw BookExploreError.requestBuildFailed(error.localizedDescription)
        }

        if built.request.options.requiresWebView ||
            nonblank(built.request.options.webJavaScript) != nil {
            throw BookExploreError.unsupportedWebView
        }
        if nonblank(built.request.options.javaScript) != nil, !hasJavaScriptExecutor {
            throw BookExploreError.requestBuildFailed("The URL option requires a JavaScript executor.")
        }

        let response: HTTPResponse
        do { response = try await httpClient.send(built.request) }
        catch { throw BookExploreError.networkFailed(error.localizedDescription) }

        let body: String
        do { body = try response.text(decoder: textDecoder) }
        catch { throw BookExploreError.responseDecodeFailed(error.localizedDescription) }

        do {
            return try bookListParser.parse(
                body: body,
                rules: rules,
                source: source,
                baseURL: response.finalURL.absoluteString,
                variables: built.variableWrites
            )
        } catch let error as BookListParseError {
            throw map(error)
        }
    }

    private func map(_ error: BookListParseError) -> BookExploreError {
        switch error {
        case let .bookListRuleFailed(message): .bookListRuleFailed(message)
        case let .fieldRuleFailed(field, message): .fieldRuleFailed(field: field, message: message)
        case let .unsupportedStructuredRule(rule): .unsupportedStructuredRule(rule)
        case .unsupportedJavaScriptNetworkHost: .unsupportedJavaScriptNetworkHost
        }
    }

    private func requiresNetworkHost(_ rule: String) -> Bool {
        let value = rule.lowercased()
        return ["java.ajax", "java.get", "java.post", "java.head"].contains { value.contains($0) }
    }

    private func nonblank(_ value: String?) -> String? {
        guard let value, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return value
    }
}
