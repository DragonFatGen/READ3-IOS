import Foundation

/// A deliberately small, platform-neutral snapshot of a JavaScript result.
/// Native engine objects must be converted before crossing this boundary.
public indirect enum JavaScriptExecutionResult: Sendable, Equatable {
    case undefined
    case null
    case boolean(Bool)
    case number(Double)
    case string(String)
    case array([JavaScriptExecutionResult])
    case object([String: JavaScriptExecutionResult])

    var ruleValue: RuleValue {
        switch self {
        case .undefined, .null:
            .none
        case let .boolean(value):
            .string(value ? "true" : "false")
        case let .number(value):
            .string(Self.numberString(value))
        case let .string(value):
            .string(value)
        case let .array(values):
            .strings(values.map(\.collectionElementString))
        case .object:
            .string(compactJSONString)
        }
    }

    var templateString: String {
        switch self {
        case .undefined, .null:
            ""
        case let .number(value) where value.isFinite && value.rounded(.towardZero) == value:
            Self.integralTemplateString(value)
        default:
            ruleValue.stringValue
        }
    }

    private var collectionElementString: String {
        switch self {
        case .undefined:
            "undefined"
        case .null:
            "null"
        case let .boolean(value):
            value ? "true" : "false"
        case let .number(value):
            Self.numberString(value)
        case let .string(value):
            value
        case .array, .object:
            compactJSONString
        }
    }

    private var compactJSONString: String {
        switch self {
        case .undefined, .null:
            return "null"
        case let .boolean(value):
            return value ? "true" : "false"
        case let .number(value):
            return value.isFinite ? Self.numberString(value) : "null"
        case let .string(value):
            return Self.quotedJSONString(value)
        case let .array(values):
            return "[" + values.map(\.compactJSONString).joined(separator: ",") + "]"
        case let .object(values):
            let members = values.keys.sorted().compactMap { key -> String? in
                guard let value = values[key], value != .undefined else { return nil }
                return Self.quotedJSONString(key) + ":" + value.compactJSONString
            }
            return "{" + members.joined(separator: ",") + "}"
        }
    }

    private static func numberString(_ value: Double) -> String {
        if value.isNaN { return "NaN" }
        if value == .infinity { return "Infinity" }
        if value == -.infinity { return "-Infinity" }
        return String(value)
    }

    private static func integralTemplateString(_ value: Double) -> String {
        if value >= Double(Int64.min), value <= Double(Int64.max) {
            return String(Int64(value))
        }
        return String(format: "%.0f", locale: Locale(identifier: "en_US_POSIX"), value)
    }

    private static func quotedJSONString(_ value: String) -> String {
        guard let data = try? JSONEncoder().encode(value),
              let result = String(data: data, encoding: .utf8) else {
            return "\"\""
        }
        return result
    }
}
