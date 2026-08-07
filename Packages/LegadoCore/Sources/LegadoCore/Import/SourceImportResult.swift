import Foundation

public struct SourceImportResult: Equatable, Sendable {
    public let source: BookSource
    public let warnings: [SourceImportWarning]
    public let migrations: [SourceMigration]
    public let normalizedJSON: Data

    public init(
        source: BookSource,
        warnings: [SourceImportWarning],
        migrations: [SourceMigration],
        normalizedJSON: Data
    ) {
        self.source = source
        self.warnings = warnings
        self.migrations = migrations
        self.normalizedJSON = normalizedJSON
    }
}
