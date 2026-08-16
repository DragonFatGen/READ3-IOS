import LegadoCore
import XCTest
@testable import LegadoIOS

@MainActor
final class SourceHealthCoordinatorTests: XCTestCase {
    func testSuccessAndEmptyResultsAreAvailable() async {
        let coordinator = SourceHealthCoordinator(service: HealthSearchService(result: .success([])))
        coordinator.test(testSource())
        await wait { coordinator.status(for: testSource().bookSourceUrl) == .available }
    }

    func testRuntimeErrorIsFailed() async {
        let coordinator = SourceHealthCoordinator(service: HealthSearchService(result: .failure(.expected)))
        coordinator.test(testSource())
        await wait {
            if case .failed = coordinator.status(for: testSource().bookSourceUrl) { return true }
            return false
        }
    }

    func testCancellationAndStaleResultAreIgnored() async {
        let service = SequencedHealthSearchService()
        let coordinator = SourceHealthCoordinator(service: service)
        coordinator.test(testSource())
        coordinator.invalidate(identity: testSource().bookSourceUrl)
        try? await Task.sleep(for: .milliseconds(80))
        XCTAssertEqual(coordinator.status(for: testSource().bookSourceUrl), .idle)
    }

    func testAllBoundsConcurrencyAtThree() async {
        let service = ConcurrencyHealthSearchService()
        let coordinator = SourceHealthCoordinator(service: service)
        let sources = (0..<8).map {
            BookSource(bookSourceUrl: "https://\($0).example", bookSourceName: "\($0)")
        }
        coordinator.testAll(sources)
        await wait(attempts: 200) {
            sources.allSatisfy { coordinator.status(for: $0.bookSourceUrl) == .available }
        }
        let maximum = await service.maximumConcurrency
        XCTAssertLessThanOrEqual(maximum, 3)
    }

    private func wait(attempts: Int = 100, until condition: @escaping () -> Bool) async {
        for _ in 0..<attempts {
            if condition() { return }
            try? await Task.sleep(for: .milliseconds(5))
        }
        XCTFail("Timed out waiting for health state")
    }
}

private struct HealthSearchService: BookSearching {
    let result: Result<[BookSearchResult], ViewModelTestError>
    func search(source: BookSource, keyword: String) async throws -> [BookSearchResult] {
        try result.get()
    }
}

private actor SequencedHealthSearchService: BookSearching {
    func search(source: BookSource, keyword: String) async throws -> [BookSearchResult] {
        try await Task.sleep(for: .milliseconds(40))
        return []
    }
}

private actor ConcurrencyHealthSearchService: BookSearching {
    private(set) var active = 0
    private(set) var maximumConcurrency = 0
    func search(source: BookSource, keyword: String) async throws -> [BookSearchResult] {
        active += 1
        maximumConcurrency = max(maximumConcurrency, active)
        defer { active -= 1 }
        try await Task.sleep(for: .milliseconds(15))
        return []
    }
}
