import Combine
import Foundation
import LegadoCore

enum SourceHealthStatus: Equatable, Sendable {
    case idle
    case testing
    case available
    case failed(String)
}

@MainActor
final class SourceHealthCoordinator: ObservableObject {
    @Published private(set) var statuses: [String: SourceHealthStatus] = [:]

    private let service: any BookSearching
    private let keyword: String
    private var tasks: [String: Task<Void, Never>] = [:]
    private var generations: [String: UUID] = [:]
    private var testAllTask: Task<Void, Never>?

    init(service: any BookSearching, keyword: String = "测试") {
        self.service = service
        self.keyword = keyword
    }

    deinit {
        tasks.values.forEach { $0.cancel() }
        testAllTask?.cancel()
    }

    func status(for identity: String) -> SourceHealthStatus { statuses[identity] ?? .idle }

    func test(_ source: BookSource) {
        let identity = source.bookSourceUrl
        tasks[identity]?.cancel()
        let generation = UUID()
        generations[identity] = generation
        statuses[identity] = .testing
        let service = service
        let keyword = keyword
        tasks[identity] = Task { [weak self] in
            let result: SourceHealthStatus
            do {
                _ = try await service.search(source: source, keyword: keyword)
                try Task.checkCancellation()
                result = .available
            } catch is CancellationError {
                return
            } catch {
                result = .failed(UserFacingError.message(for: error, fallback: "测试失败"))
            }
            guard let self, self.generations[identity] == generation else { return }
            self.statuses[identity] = result
            self.tasks[identity] = nil
        }
    }

    func testAll(_ sources: [BookSource]) {
        cancelAll()
        let uniqueSources = Dictionary(sources.map { ($0.bookSourceUrl, $0) }, uniquingKeysWith: { _, rhs in rhs })
            .values.sorted { $0.bookSourceUrl < $1.bookSourceUrl }
        let generation = UUID()
        uniqueSources.forEach {
            generations[$0.bookSourceUrl] = generation
            statuses[$0.bookSourceUrl] = .testing
        }
        let service = service
        let keyword = keyword
        testAllTask = Task { [weak self] in
            await withTaskGroup(of: (String, SourceHealthStatus).self) { group in
                var iterator = uniqueSources.makeIterator()
                for _ in 0..<3 {
                    guard let source = iterator.next() else { break }
                    Self.addTest(source, service: service, keyword: keyword, to: &group)
                }
                while let (identity, status) = await group.next() {
                    guard !Task.isCancelled else { group.cancelAll(); return }
                    if let self, self.generations[identity] == generation {
                        self.statuses[identity] = status
                    }
                    if let source = iterator.next() {
                        Self.addTest(source, service: service, keyword: keyword, to: &group)
                    }
                }
            }
        }
    }

    func invalidate(identity: String) {
        tasks[identity]?.cancel()
        tasks[identity] = nil
        generations[identity] = UUID()
        statuses[identity] = .idle
    }

    func cancelAll() {
        tasks.values.forEach { $0.cancel() }
        tasks.removeAll()
        testAllTask?.cancel()
        testAllTask = nil
        for identity in statuses.keys where statuses[identity] == .testing {
            generations[identity] = UUID()
            statuses[identity] = .idle
        }
    }

    private static func addTest(
        _ source: BookSource,
        service: any BookSearching,
        keyword: String,
        to group: inout TaskGroup<(String, SourceHealthStatus)>
    ) {
        group.addTask {
            do {
                _ = try await service.search(source: source, keyword: keyword)
                try Task.checkCancellation()
                return (source.bookSourceUrl, .available)
            } catch is CancellationError {
                return (source.bookSourceUrl, .idle)
            } catch {
                return (
                    source.bookSourceUrl,
                    .failed(UserFacingError.message(for: error, fallback: "测试失败"))
                )
            }
        }
    }
}
