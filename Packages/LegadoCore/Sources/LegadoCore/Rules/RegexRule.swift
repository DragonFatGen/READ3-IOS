public struct RegexRule: Equatable, Sendable {
    public enum Purpose: Equatable, Sendable {
        /// All-in-one element extraction. Patterns are applied as a chain.
        case extraction(patterns: [String])
        /// Post-process the preceding expression.
        case replacement(pattern: String, replacement: String, replaceFirst: Bool)
    }

    public let purpose: Purpose

    public init(purpose: Purpose) {
        self.purpose = purpose
    }
}
