import Foundation

public struct BookSourceImporter: Sendable {
    public init() {}

    /// Imports exactly one source. Arrays remain invalid for compatibility with the original API.
    public func importSource(from data: Data) throws -> SourceImportResult {
        let rawValue: JSONValue
        do {
            rawValue = try JSONDecoder().decode(JSONValue.self, from: data)
        } catch {
            throw SourceImportError.invalidJSON
        }
        return try importSource(from: rawValue)
    }

    /// Imports an object or array using strict failure semantics.
    public func importSources(from data: Data) throws -> [SourceImportResult] {
        try importSources(from: data, policy: .strict).results
    }

    /// Imports an object or array and reports indexed element failures in lenient mode.
    public func importSources(
        from data: Data,
        policy: SourceImportPolicy
    ) throws -> SourceBatchImportResult {
        let rawValue: JSONValue
        do {
            rawValue = try JSONDecoder().decode(JSONValue.self, from: data)
        } catch {
            throw SourceImportError.invalidJSON
        }

        switch rawValue {
        case .object:
            return SourceBatchImportResult(
                results: [try importSource(from: rawValue)],
                failures: []
            )
        case let .array(values):
            var results: [SourceImportResult] = []
            var failures: [SourceBatchImportError] = []
            results.reserveCapacity(values.count)

            for (index, value) in values.enumerated() {
                do {
                    results.append(try importSource(from: value))
                } catch let sourceError as SourceImportError {
                    let failure = SourceBatchImportError(
                        index: index,
                        sourceError: sourceError
                    )
                    if policy == .strict {
                        throw failure
                    }
                    failures.append(failure)
                }
            }
            return SourceBatchImportResult(results: results, failures: failures)
        default:
            throw SourceImportError.topLevelMustBeObject
        }
    }

    private func importSource(from rawValue: JSONValue) throws -> SourceImportResult {
        let normalization = try LegacySourceNormalizer().normalize(rawValue)
        let intermediateData: Data
        do {
            intermediateData = try JSONEncoder().encode(normalization.value)
        } catch {
            throw SourceImportError.normalizedJSONEncodingFailed
        }

        let source: BookSource
        do {
            source = try JSONDecoder().decode(BookSource.self, from: intermediateData)
        } catch let error as DecodingError {
            throw SourceImportError.normalizedSourceDecodingFailed(
                field: Self.fieldPath(from: error)
            )
        } catch {
            throw SourceImportError.normalizedSourceDecodingFailed(field: nil)
        }

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let normalizedJSON: Data
        do {
            normalizedJSON = try encoder.encode(source)
        } catch {
            throw SourceImportError.normalizedJSONEncodingFailed
        }

        return SourceImportResult(
            source: source,
            warnings: normalization.warnings,
            migrations: normalization.migrations,
            normalizedJSON: normalizedJSON
        )
    }

    private static func fieldPath(from error: DecodingError) -> String? {
        let codingPath: [any CodingKey]
        switch error {
        case let .dataCorrupted(context), let .keyNotFound(_, context),
             let .typeMismatch(_, context), let .valueNotFound(_, context):
            codingPath = context.codingPath
        @unknown default:
            return nil
        }
        let path = codingPath.map(\.stringValue).joined(separator: ".")
        return path.isEmpty ? nil : path
    }
}
