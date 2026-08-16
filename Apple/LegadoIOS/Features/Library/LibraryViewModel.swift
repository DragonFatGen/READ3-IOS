import Combine
import Foundation

struct LibraryRefreshSummary: Equatable, Sendable {
    var succeeded: Int
    var failed: Int
    var updates: [LibraryBookUpdateNotification]
    var failures: [LibraryUpdateFailure]

    init(
        succeeded: Int,
        failed: Int,
        updates: [LibraryBookUpdateNotification] = [],
        failures: [LibraryUpdateFailure] = []
    ) {
        self.succeeded = succeeded
        self.failed = failed
        self.updates = updates
        self.failures = failures
    }

    var checkedCount: Int { succeeded + failed }
    var updatedBookCount: Int { updates.count }
    var newChapterCount: Int { updates.reduce(0) { $0 + $1.newChapterCount } }

    static let empty = LibraryRefreshSummary(succeeded: 0, failed: 0)
}

struct LibraryUpdateFailure: Identifiable, Equatable, Sendable {
    let bookID: String
    let bookName: String
    let message: String

    var id: String { bookID }
}

private struct LibraryUpdateOutcome: Sendable {
    let bookID: String
    let bookName: String
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
    private var refreshAllTask: Task<LibraryRefreshSummary, Never>?
    private var refreshAllID: UUID?

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
        refreshAllTask?.cancel()
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
            failed: outcome.errorMessage == nil ? 0 : 1,
            updates: notificationUpdates(for: outcome),
            failures: failureDetails(for: outcome)
        )
    }

    func refreshAll() async -> LibraryRefreshSummary {
        if let refreshAllTask {
            return await withTaskCancellationHandler {
                await refreshAllTask.value
            } onCancel: {
                refreshAllTask.cancel()
            }
        }
        let id = UUID()
        let task = Task { [weak self] in await self?.performRefreshAll() ?? .empty }
        refreshAllID = id
        refreshAllTask = task
        let summary = await withTaskCancellationHandler {
            await task.value
        } onCancel: {
            task.cancel()
        }
        if refreshAllID == id {
            refreshAllTask = nil
            refreshAllID = nil
        }
        return summary
    }

    func cancelRefreshes() {
        refreshAllTask?.cancel()
        refreshAllTask = nil
        refreshAllID = nil
        singleTasks.values.forEach { $0.cancel() }
        singleTasks.removeAll()
    }

    private func performRefreshAll() async -> LibraryRefreshSummary {
        isRefreshingAll = true
        lastSummary = nil
        let books = repository.books
        checkingBookIDs.formUnion(books.map(\.id))
        defer {
            checkingBookIDs.subtract(books.map(\.id))
            isRefreshingAll = false
        }

        var summary = LibraryRefreshSummary.empty
        var startIndex = 0
        while startIndex < books.count, !Task.isCancelled {
            let endIndex = min(startIndex + Self.maximumConcurrentChecks, books.count)
            let batch = Array(books[startIndex..<endIndex])
            await withTaskGroup(of: LibraryUpdateOutcome.self) { group in
                for book in batch {
                    let checker = checker
                    let source = sourceStore.source(for: book.source.bookSourceUrl)
                    group.addTask {
                        guard let source else {
                            return LibraryUpdateOutcome(
                                bookID: book.id, bookName: book.name,
                                result: nil, errorMessage: "原书源已删除"
                            )
                        }
                        do {
                            let result = try await checker.checkUpdate(for: book, source: source)
                            return LibraryUpdateOutcome(
                                bookID: book.id, bookName: book.name,
                                result: result, errorMessage: nil
                            )
                        } catch is CancellationError {
                            return LibraryUpdateOutcome(
                                bookID: book.id, bookName: book.name,
                                result: nil, errorMessage: nil
                            )
                        } catch {
                            return LibraryUpdateOutcome(
                                bookID: book.id, bookName: book.name, result: nil,
                                errorMessage: Self.updateErrorMessage(error)
                            )
                        }
                    }
                }
                while let outcome = await group.next() {
                    guard !Task.isCancelled else { group.cancelAll(); return }
                    if outcome.result != nil {
                        summary.succeeded += 1
                        summary.updates.append(contentsOf: notificationUpdates(for: outcome))
                    } else if outcome.errorMessage != nil {
                        summary.failed += 1
                        summary.failures.append(contentsOf: failureDetails(for: outcome))
                    }
                    apply(outcome)
                    checkingBookIDs.remove(outcome.bookID)
                }
            }
            startIndex = endIndex
        }
        if !Task.isCancelled { lastSummary = summary }
        return summary
    }

    private func check(_ book: LibraryBook) async -> LibraryUpdateOutcome {
        guard let source = sourceStore.source(for: book.source.bookSourceUrl) else {
            return LibraryUpdateOutcome(
                bookID: book.id, bookName: book.name,
                result: nil, errorMessage: "原书源已删除"
            )
        }
        do {
            return LibraryUpdateOutcome(
                bookID: book.id, bookName: book.name,
                result: try await checker.checkUpdate(for: book, source: source),
                errorMessage: nil
            )
        } catch is CancellationError {
            return LibraryUpdateOutcome(
                bookID: book.id, bookName: book.name, result: nil, errorMessage: nil
            )
        } catch {
            return LibraryUpdateOutcome(
                bookID: book.id, bookName: book.name, result: nil,
                errorMessage: Self.updateErrorMessage(error)
            )
        }
    }

    private func notificationUpdates(for outcome: LibraryUpdateOutcome) -> [LibraryBookUpdateNotification] {
        guard let result = outcome.result, result.newChapterCount > 0 else { return [] }
        return [LibraryBookUpdateNotification(
            bookID: outcome.bookID,
            bookName: outcome.bookName,
            newChapterCount: result.newChapterCount,
            latestChapterName: result.latestChapterName
        )]
    }

    private func failureDetails(for outcome: LibraryUpdateOutcome) -> [LibraryUpdateFailure] {
        guard let message = outcome.errorMessage else { return [] }
        return [LibraryUpdateFailure(
            bookID: outcome.bookID,
            bookName: outcome.bookName,
            message: message
        )]
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
