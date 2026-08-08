public enum RuleValue: Sendable, Equatable {
    case none
    case string(String)
    case strings([String])

    public var isEmpty: Bool {
        switch self {
        case .none: true
        case let .string(value): value.isEmpty
        case let .strings(values): values.isEmpty
        }
    }

    public var stringValue: String {
        switch self {
        case .none: ""
        case let .string(value): value
        case let .strings(values): values.joined(separator: "\n")
        }
    }

    public var stringValues: [String] {
        switch self {
        case .none: []
        case let .string(value): [value]
        case let .strings(values): values
        }
    }
}

public struct RuleExecutionInput: Sendable, Equatable {
    public let value: RuleValue

    public init(_ value: RuleValue) {
        self.value = value
    }
}
