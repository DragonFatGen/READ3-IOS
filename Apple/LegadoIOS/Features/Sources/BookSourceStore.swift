import Combine
import Foundation
import LegadoCore

@MainActor
final class BookSourceStore: ObservableObject {
    @Published private(set) var sources: [BookSource] = []
    @Published var errorMessage: String?

    private let importer: BookSourceImporter
    private let defaults: UserDefaults
    private let storageKey: String

    init(
        importer: BookSourceImporter = BookSourceImporter(),
        defaults: UserDefaults = .standard,
        storageKey: String = "book.sources.v1"
    ) {
        self.importer = importer
        self.defaults = defaults
        self.storageKey = storageKey
        if let data = defaults.data(forKey: storageKey),
           let decoded = try? JSONDecoder().decode([BookSource].self, from: data) {
            sources = decoded
        }
    }

    func importSources(from data: Data) {
        do {
            let result = try importer.importSources(from: data, mode: .lenient)
            for imported in result.successes.map(\.source) {
                if let index = sources.firstIndex(where: {
                    $0.bookSourceUrl == imported.bookSourceUrl
                }) {
                    sources[index] = imported
                } else {
                    sources.append(imported)
                }
            }
            errorMessage = result.failures.isEmpty
                ? nil
                : "部分书源导入失败（\(result.failures.count) 个）"
            persist()
        } catch {
            errorMessage = UserFacingError.message(for: error, fallback: "无法导入书源")
        }
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(sources) else { return }
        defaults.set(data, forKey: storageKey)
    }
}
