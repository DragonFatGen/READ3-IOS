public struct RuleVariableStore: Sendable, Equatable {
    private var values: [String: String]

    public init(_ values: [String: String] = [:]) {
        self.values = values
    }

    public subscript(key: String) -> String? {
        get { values[key] }
        set { values[key] = newValue }
    }
}

public struct RuleExecutionContext: Sendable, Equatable {
    public let baseUrl: String
    public var sourceVariables: RuleVariableStore
    public var temporaryVariables: RuleVariableStore
    public var currentResult: RuleValue
    public var captureGroups: [String]
    public let errorPolicy: RuleParseContext.ErrorPolicy

    public init(
        baseUrl: String = "",
        sourceVariables: [String: String] = [:],
        temporaryVariables: [String: String] = [:],
        currentResult: RuleValue = .none,
        captureGroups: [String] = [],
        errorPolicy: RuleParseContext.ErrorPolicy = .legadoCompatible
    ) {
        self.baseUrl = baseUrl
        self.sourceVariables = RuleVariableStore(sourceVariables)
        self.temporaryVariables = RuleVariableStore(temporaryVariables)
        self.currentResult = currentResult
        self.captureGroups = captureGroups
        self.errorPolicy = errorPolicy
    }

    public func variable(named key: String) -> String? {
        switch key {
        case "baseUrl": baseUrl
        case "result": currentResult.stringValue
        default: temporaryVariables[key] ?? sourceVariables[key]
        }
    }

    public mutating func setTemporaryVariable(_ value: String, named key: String) {
        temporaryVariables[key] = value
    }
}
