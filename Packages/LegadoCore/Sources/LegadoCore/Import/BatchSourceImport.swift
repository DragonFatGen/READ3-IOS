import Foundation

public enum BatchImportMode: Equatable, Sendable {
    case strict
    case lenient
}

public struct BatchSourceImportFailure: Equatable, Sendable {
    public let index: Int
    public let error: SourceImportError

    public init(index: Int, error: SourceImportError) {
        self.index = index
        self.error = error
    }
}

public struct BatchSourceImportResult: Equatable, Sendable {
    public let successes: [SourceImportResult]
    public let failures: [BatchSourceImportFailure]

    public init(
        successes: [SourceImportResult],
        failures: [BatchSourceImportFailure]
    ) {
        self.successes = successes
        self.failures = failures
    }
}

public enum BatchSourceImportError: Error, Equatable, Sendable {
    case elementFailed(index: Int, error: SourceImportError)
}

extension BatchSourceImportError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case let .elementFailed(index, error):
            return "Book source at array index \(index) failed to import: \(error.localizedDescription)"
        }
    }
}
