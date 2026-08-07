import Foundation

enum FixtureLoader {
    static func data(named name: String, directory: String = "book-source") throws -> Data {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let fixtureURL = repositoryRoot
            .appendingPathComponent("TestSources")
            .appendingPathComponent(directory)
            .appendingPathComponent(name)
        return try Data(contentsOf: fixtureURL)
    }
}
