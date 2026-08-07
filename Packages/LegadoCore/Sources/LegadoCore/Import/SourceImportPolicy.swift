public enum SourceImportPolicy: Equatable, Sendable {
    case strict
    case lenient
}

public typealias SourceBatchImportPolicy = SourceImportPolicy
