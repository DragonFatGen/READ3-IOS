import Foundation

public struct BookSourceSearchRuntime: Sendable {
    private let httpClient: any HTTPClient
    private let requestBuilder: RequestBuilder
    private let bookListParser: BookListParser
    private let textDecoder: any TextDecoder

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
    }

    public func search(
        source: BookSource,
        keyword: String,
        page: Int = 1
    ) async throws -> [BookSearchResult] {
        var diagnostic = SearchDiagnostic()
        return try await search(source: source, keyword: keyword, page: page, diagnostic: &diagnostic)
    }

    /// The diagnostic remains available when a stage throws; existing errors are unchanged.
    public func search(
        source: BookSource,
        keyword: String,
        page: Int = 1,
        diagnostic: inout SearchDiagnostic
    ) async throws -> [BookSearchResult] {
        diagnostic = SearchDiagnostic()
        guard let searchURL = nonblank(source.searchUrl), let rules = source.ruleSearch,
              nonblank(rules.bookList) != nil else {
            throw BookSearchError.searchNotSupported
        }
        if requiresNetworkHost(searchURL) { throw BookSearchError.unsupportedJavaScriptNetworkHost }

        diagnostic.lastStage = .requestBuild
        let built: RequestBuildResult
        do {
            built = try await requestBuilder.buildResult(
                searchURL,
                source: source,
                context: RequestBuildContext(
                    keyword: keyword,
                    page: page,
                    sourceURL: source.bookSourceUrl,
                    baseURL: source.bookSourceUrl,
                    sourceIdentifier: source.bookSourceUrl
                )
            )
        } catch {
            throw BookSearchError.requestBuildFailed(
                error.localizedDescription, diagnostic: .construction(error)
            )
        }

        diagnostic.lastStage = .request
        let response: HTTPResponse
        do { response = try await httpClient.send(built.request) }
        catch {
            throw BookSearchError.networkFailed(
                error.localizedDescription, diagnostic: .network(error)
            )
        }

        diagnostic.recordResponse(response)
        diagnostic.lastStage = .responseDecode
        let body: String
        do { body = try response.text(decoder: textDecoder) }
        catch { throw BookSearchError.responseDecodeFailed(error.localizedDescription) }

        if diagnostic.responseContentType == .html {
            diagnostic.pageHint = SearchPageHint.classify(body)
        }
        do {
            return try bookListParser.parse(
                body: body,
                rules: rules,
                source: source,
                baseURL: response.finalURL.absoluteString,
                variables: built.variableWrites,
                diagnostic: &diagnostic
            )
        } catch let error as BookListParseError {
            throw map(error)
        }
    }

    private func map(_ error: BookListParseError) -> BookSearchError {
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
