import Foundation

public struct URLResolver: Sendable {
    public init() {}

    public func resolve(_ value: String, against baseURL: String) -> String {
        let value = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return baseURL }
        if value.hasPrefix("//"), let base = URL(string: baseURL), let scheme = base.scheme {
            return "\(scheme):\(value)"
        }
        if let direct = URL(string: value), direct.scheme != nil { return direct.absoluteString }
        guard let base = URL(string: baseURL),
              let resolved = URL(string: value, relativeTo: base)?.absoluteURL else { return value }
        return resolved.absoluteString
    }
}
