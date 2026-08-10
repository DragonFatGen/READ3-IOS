public struct JavaScriptExecutionContext: Sendable, Equatable {
    /// The value produced by the preceding rule stage and exposed as `result`.
    public let result: RuleValue
    public let baseUrl: String
    /// The minimum source identity needed by a future AnalyzeUrl-style host.
    /// It is a value snapshot, not a `BookSource` or persistence object.
    public let source: JavaScriptSourceSnapshot?
    public let sourceVariables: [String: String]
    public let temporaryVariables: [String: String]

    public init(
        result: RuleValue,
        baseUrl: String,
        source: JavaScriptSourceSnapshot? = nil,
        sourceVariables: [String: String] = [:],
        temporaryVariables: [String: String] = [:]
    ) {
        self.result = result
        self.baseUrl = baseUrl
        self.source = source
        self.sourceVariables = sourceVariables
        self.temporaryVariables = temporaryVariables
    }

    init(ruleContext: RuleExecutionContext) {
        self.init(
            result: ruleContext.currentResult,
            baseUrl: ruleContext.baseUrl,
            source: ruleContext.javaScriptSource,
            sourceVariables: ruleContext.sourceVariables.snapshot,
            temporaryVariables: ruleContext.temporaryVariables.snapshot
        )
    }
}

/// Source data actually consumed by Android's AnalyzeUrl-style `java.ajax`
/// path. Cookie scope uses `identifier`; no source model or mutable state crosses
/// the JavaScript executor boundary.
public struct JavaScriptSourceSnapshot: Sendable, Equatable {
    public let identifier: String
    public let url: String
    public let header: String?

    public init(identifier: String, url: String, header: String? = nil) {
        self.identifier = identifier
        self.url = url
        self.header = header
    }
}
