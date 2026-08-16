import Combine
import Foundation

struct LibraryRefreshSummary: Equatable {
    var succeeded: Int
    var failed: Int
}

private struct LibraryUpdateOutcome: Sendable {
    let bookID: String
    let result: BookUpdateResult?
    let errorMessage: String?
}

@MainActor
final class LibraryViewModel: ObservableObject {
    static let maximumConcurrentChecks = 3

    @Published private(set) var checkingBookIDs: Set<String> = []
    @Published private(set) var isRefreshingAll = false
    @Published private(set) var lastSummary: LibraryRefreshSummary?

    private let repository: LibraryRepository
    private let sourceStore: BookSourceStore
    private let checker: any BookUpdateChecking
    private var singleTasks: [String: Task<Void, Never>] = [:]
    private var batchGeneration = UUID()

    init(
        repository: LibraryRepository,
        sourceStore: BookSourceStore,
        checker: any BookUpdateChecking
    ) {
        self.repository = repository
        self.sourceStore = sourceStore
        self.checker = checker
    }

    deinit {
        singleTasks.values.forEach { $0.cancel() }
    }

    func refresh(_ book: LibraryBook) {
        singleTasks[book.id]?.cancel()
        singleTasks[book.id] = Task { [weak self] in
            await self?.refreshBook(book)
            self?.singleTasks[book.id] = nil
        }
    }

    func refreshBook(_ book: LibraryBook) async {
        guard !checkingBookIDs.contains(book.id) else { return }
        checkingBookIDs.insert(book.id)
        defer { checkingBookIDs.remove(book.id) }
        let outcome = await check(book)
        apply(outcome)
        guard outcome.result != nil || outcome.errorMessage != nil else { return }
        lastSummary = LibraryRefreshSummary(
            succeeded: outcome.result == nil ? 0 : 1,
            failed: outcome.errorMessage == nil ? 0 : 1
        )
    }

    func refreshAll() async {
        guard !isRefreshingAll else { return }
        isRefreshingAll = true
        lastSummary = nil
        let generation = UUID()
        batchGeneration = generation
        let books = repository.books
        checkingBookIDs.formUnion(books.map(\.id))
        defer {
            checkingBookIDs.subtract(books.map(\.id))
            isRefreshingAll = false
        }

        var summary = LibraryRefreshSummary(succeeded: 0, failed: 0)
        var startIndex = 0
        while startIndex < books.count, !Task.isCancelled, batchGeneration == generation {
            let endIndex = min(startIndex + Self.maximumConcurrentChecks, books.count)
            let batch = Array(books[startIndex..<endIndex])
            await withTaskGroup(of: LibraryUpdateOutcome.self) { group in
                for book in batch {
                    let checker = checker
                    let source = sourceStore.source(for: book.source.bookSourceUrl)
                    group.addTask {
                        guard let source else {
                            return LibraryUpdateOutcome(
                                bookID: book.id, result: nil, errorMessage: "书源不可用"
                            )
                        }
                        do {
                            let result = try await checker.checkUpdate(for: book, source: source)
                            return LibraryUpdateOutcome(bookID: book.id, result: result, errorMessage: nil)
                        } catch is CancellationError {
                            return LibraryUpdateOutcome(bookID: book.id, result: nil, errorMessage: nil)
                        } catch {
                            return LibraryUpdateOutcome(
                                bookID: book.id,
                                result: nil,
                                errorMessage: Self.updateErrorMessage(error)
                            )
                        }
                    }
                }
                while let outcome = await group.next() {
                    guard !Task.isCancelled, batchGeneration == generation else {
                        group.cancelAll()
                        return
                    }
                    if outcome.result != nil {
                        summary.succeeded += 1
                    } else if outcome.errorMessage != nil {
                        summary.failed += 1
                    }
                    apply(outcome)
                    checkingBookIDs.remove(outcome.bookID)
                }
            }
            startIndex = endIndex
        }
        if !Task.isCancelled, batchGeneration == generation { lastSummary = summary }
    }

    func cancelRefreshes() {
        batchGeneration = UUID()
        singleTasks.values.forEach { $0.cancel() }
        singleTasks.removeAll()
    }

    private func check(_ book: LibraryBook) async -> LibraryUpdateOutcome {
        guard let source = sourceStore.source(for: book.source.bookSourceUrl) else {
            return LibraryUpdateOutcome(bookID: book.id, result: nil, errorMessage: "书源不可用")
        }
        do {
            return LibraryUpdateOutcome(
                bookID: book.id,
                result: try await checker.checkUpdate(for: book, source: source),
                errorMessage: nil
            )
        } catch is CancellationError {
            return LibraryUpdateOutcome(bookID: book.id, result: nil, errorMessage: nil)
        } catch {
            return LibraryUpdateOutcome(
                bookID: book.id,
                result: nil,
                errorMessage: Self.updateErrorMessage(error)
            )
        }
    }

    private func apply(_ outcome: LibraryUpdateOutcome) {
        if let result = outcome.result {
            repository.applyUpdateCheck(bookID: outcome.bookID, result: result)
        } else if let message = outcome.errorMessage {
            repository.recordUpdateFailure(bookID: outcome.bookID, message: message)
        }
    }

    nonisolated private static func updateErrorMessage(_ error: Error) -> String {
        if error is BookUpdateCheckError { return "书源返回的目录为空" }
        return "获取目录失败"
    }
}
