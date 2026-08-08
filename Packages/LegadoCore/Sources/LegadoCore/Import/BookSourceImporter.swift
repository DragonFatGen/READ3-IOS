import Foundation

public struct BookSourceImporter: Sendable {
    public init() {}

    /// Imports either one source object or an ordered array of source objects.
    /// Each array element is processed through ``importSource(from:)`` independently.
    public func importSources(
        from data: Data,
        mode: BatchImportMode = .strict
    ) throws -> BatchSourceImportResult {
        let rawValue: JSONValue
        do {
            rawValue = try JSONDecoder().decode(JSONValue.self, from: data)
        } catch {
            throw SourceImportError.invalidJSON
        }

        switch rawValue {
        case .object:
            return BatchSourceImportResult(
                successes: [try importSource(from: data)],
                failures: []
            )
        case let .array(values):
            var successes: [SourceImportResult] = []
            var failures: [BatchSourceImportFailure] = []

            for (index, value) in values.enumerated() {
                do {
                    let elementData = try JSONEncoder().encode(value)
                    successes.append(try importSource(from: elementData))
                } catch let error as SourceImportError {
                    if mode == .strict {
                        throw BatchSourceImportError.elementFailed(index: index, error: error)
                    }
                    failures.append(BatchSourceImportFailure(index: index, error: error))
                } catch {
                    let importError = SourceImportError.normalizedJSONEncodingFailed
                    if mode == .strict {
                        throw BatchSourceImportError.elementFailed(index: index, error: importError)
                    }
                    failures.append(BatchSourceImportFailure(index: index, error: importError))
                }
            }

            return BatchSourceImportResult(successes: successes, failures: failures)
        default:
            throw SourceImportError.topLevelMustBeObjectOrArray
        }
    }

    public func importSource(from data: Data) throws -> SourceImportResult {
        let rawValue: JSONValue
        do {
            rawValue = try JSONDecoder().decode(JSONValue.self, from: data)
        } catch {
            throw SourceImportError.invalidJSON
        }

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
