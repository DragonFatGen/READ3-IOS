import Foundation

public enum ExploreURLParserError: Error, Sendable, Equatable {
    case javaScriptUnavailable
    case javaScriptFailed(String)
    case invalidJSONArray(String)
    case unsupportedJavaScriptNetworkHost
}

extension ExploreURLParserError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .javaScriptUnavailable:
            "The explore category definition requires a JavaScript executor."
        case let .javaScriptFailed(message):
            "Explore category JavaScript failed: \(message)"
        case let .invalidJSONArray(message):
            "Explore category JSON is invalid: \(message)"
        case .unsupportedJavaScriptNetworkHost:
            "Explore categories require the deferred production JavaScript network host."
        }
    }
}

public struct ExploreURLParser: Sendable {
    private let javaScriptExecutor: (any RuleJavaScriptExecutor)?

    public init(javaScriptExecutor: (any RuleJavaScriptExecutor)? = nil) {
        self.javaScriptExecutor = javaScriptExecutor
    }

    public func parse(_ definition: String, source: BookSource? = nil) throws -> [ExploreKind] {
        var value = definition
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if isJavaScriptDefinition(trimmed) {
            if requiresNetworkHost(trimmed) {
                throw ExploreURLParserError.unsupportedJavaScriptNetworkHost
            }
            guard let javaScriptExecutor else { throw ExploreURLParserError.javaScriptUnavailable }
            let script = javaScriptBody(trimmed)
            let context = JavaScriptExecutionContext(
                result: .string(definition),
                baseUrl: source?.bookSourceUrl ?? "",
                source: source.map {
                    JavaScriptSourceSnapshot(
                        identifier: $0.bookSourceUrl,
                        url: $0.bookSourceUrl,
                        header: $0.header
                    )
                }
            )
            do {
                value = try javaScriptExecutor.execute(script: script, context: context)
                    .ruleValue.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            } catch {
                throw ExploreURLParserError.javaScriptFailed(error.localizedDescription)
            }
        }

        let resolved = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !resolved.isEmpty else { return [] }
        if resolved.first == "[" {
            do {
                return try JSONDecoder().decode([ExploreKind].self, from: Data(resolved.utf8))
            } catch {
                throw ExploreURLParserError.invalidJSONArray(error.localizedDescription)
            }
        }

        return resolved
            .components(separatedBy: try categorySeparator())
            .filter { !$0.isEmpty }
            .map { item in
                let parts = item.components(separatedBy: "::")
                return ExploreKind(
                    title: parts[0],
                    url: parts.count > 1 ? parts[1] : nil
                )
            }
    }

    private func categorySeparator() throws -> NSRegularExpression {
        try NSRegularExpression(pattern: "(?:&&|\\n)+")
    }

    private func isJavaScriptDefinition(_ value: String) -> Bool {
        value.lowercased().hasPrefix("@js:") || value.lowercased().hasPrefix("<js>")
    }

    private func requiresNetworkHost(_ value: String) -> Bool {
        let value = value.lowercased()
        return ["java.ajax", "java.get", "java.post", "java.head"].contains { value.contains($0) }
    }

    private func javaScriptBody(_ value: String) -> String {
        if value.lowercased().hasPrefix("@js:") {
            return String(value.dropFirst(4))
        }
        let body = String(value.dropFirst(4))
        guard body.lowercased().hasSuffix("</js>") else { return body }
        return String(body.dropLast(5))
    }
}

private extension String {
    func components(separatedBy expression: NSRegularExpression) -> [String] {
        let range = NSRange(startIndex..., in: self)
        var result: [String] = []
        var cursor = startIndex
        for match in expression.matches(in: self, range: range) {
            guard let matchRange = Range(match.range, in: self) else { continue }
            result.append(String(self[cursor..<matchRange.lowerBound]))
            cursor = matchRange.upperBound
        }
        result.append(String(self[cursor...]))
        return result
    }
}
