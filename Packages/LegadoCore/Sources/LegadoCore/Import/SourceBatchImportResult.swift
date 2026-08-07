public struct SourceBatchImportError: Error, Equatable, Sendable {
    public let index: Int
    public let sourceError: SourceImportError

    public var error: SourceImportError { sourceError }
    public var underlyingError: SourceImportError { sourceError }

    public init(index: Int, sourceError: SourceImportError) {
        self.index = index
        self.sourceError = sourceError
    }
}

public struct SourceBatchImportResult: Equatable, Sendable {
    public let results: [SourceImportResult]
    public let failures: [SourceBatchImportError]

    public var successes: [SourceImportResult] { results }
    public var successfulResults: [SourceImportResult] { results }

    public init(
        results: [SourceImportResult],
        failures: [SourceBatchImportError]
    ) {
        self.results = results
        self.failures = failures
    }
}
