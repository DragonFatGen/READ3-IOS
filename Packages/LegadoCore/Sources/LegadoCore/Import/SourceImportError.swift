import Foundation

public enum SourceImportError: Error, Equatable, Sendable {
    case invalidJSON
    case topLevelMustBeObject
    case invalidRuleJSONString(field: String)
    case invalidField(field: String, expected: String)
    case normalizedSourceDecodingFailed(field: String?)
    case normalizedJSONEncodingFailed
}

extension SourceImportError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .invalidJSON:
            return "The source data is not valid JSON."
        case .topLevelMustBeObject:
            return "A single imported book source must be a JSON object."
        case let .invalidRuleJSONString(field):
            return "The JSON string in \(field) is not a rule object."
        case let .invalidField(field, expected):
            return "The field \(field) must be \(expected)."
        case let .normalizedSourceDecodingFailed(field):
            return "The normalized source could not be decoded\(field.map { " at \($0)" } ?? "")."
        case .normalizedJSONEncodingFailed:
            return "The normalized source could not be encoded as JSON."
        }
    }
}
