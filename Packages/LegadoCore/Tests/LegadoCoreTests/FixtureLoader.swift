import Foundation

enum FixtureLoader {
    static func data(named name: String) throws -> Data {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let fixtureURL = repositoryRoot
            .appendingPathComponent("TestSources")
            .appendingPathComponent("book-source")
            .appendingPathComponent(name)
        return try Data(contentsOf: fixtureURL)
    }
}
