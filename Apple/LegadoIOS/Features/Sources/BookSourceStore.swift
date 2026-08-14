import Combine
import Foundation
import LegadoCore

@MainActor
final class BookSourceStore: ObservableObject {
    @Published private(set) var sources: [BookSource] = []
    @Published var errorMessage: String?

    private let importer: BookSourceImporter

    init(importer: BookSourceImporter = BookSourceImporter()) {
        self.importer = importer
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
        } catch {
            errorMessage = UserFacingError.message(for: error, fallback: "无法导入书源")
        }
    }
}
