import Foundation

@MainActor
protocol ReaderAnnotationStoring: AnyObject {
    func annotations(for bookID: String) -> [ReaderAnnotation]
    func save(_ annotation: ReaderAnnotation)
    func remove(id: UUID)
    func removeAll(for bookID: String)
}

@MainActor
final class ReaderAnnotationRepository: ReaderAnnotationStoring {
    private let fileURL: URL
    private var storedAnnotations: [ReaderAnnotation]
    private(set) var lastPersistenceError: Error?

    init(fileURL: URL? = nil) {
        self.fileURL = fileURL ?? Self.defaultFileURL()
        storedAnnotations = Self.load(from: self.fileURL)
    }

    func annotations(for bookID: String) -> [ReaderAnnotation] {
        storedAnnotations
            .filter { $0.bookID == bookID }
            .sorted {
                if $0.chapterIndex != $1.chapterIndex {
                    return $0.chapterIndex < $1.chapterIndex
                }
                if $0.utf16Location != $1.utf16Location {
                    return $0.utf16Location < $1.utf16Location
                }
                return $0.createdAt < $1.createdAt
            }
    }

    func save(_ annotation: ReaderAnnotation) {
        if let index = storedAnnotations.firstIndex(where: { $0.id == annotation.id }) {
            storedAnnotations[index] = annotation
        } else {
            storedAnnotations.append(annotation)
        }
        persist()
    }

    func remove(id: UUID) {
        storedAnnotations.removeAll { $0.id == id }
        persist()
    }

    func removeAll(for bookID: String) {
        storedAnnotations.removeAll { $0.bookID == bookID }
        persist()
    }

    private func persist() {
        do {
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.sortedKeys]
            try encoder.encode(storedAnnotations).write(to: fileURL, options: .atomic)
            lastPersistenceError = nil
        } catch {
            // Keep the in-memory collection available when persistence is temporarily unavailable.
            lastPersistenceError = error
        }
    }

    private static func load(from fileURL: URL) -> [ReaderAnnotation] {
        guard let data = try? Data(contentsOf: fileURL) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode([ReaderAnnotation].self, from: data)) ?? []
    }

    private static func defaultFileURL() -> URL {
        let base = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        )[0]
        return base
            .appendingPathComponent("ReaderAnnotations", isDirectory: true)
            .appendingPathComponent("annotations.json")
    }
}
