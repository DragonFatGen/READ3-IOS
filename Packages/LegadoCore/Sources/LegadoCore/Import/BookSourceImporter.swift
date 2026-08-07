import Foundation

public struct BookSourceImporter: Sendable {
    public init() {}

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
