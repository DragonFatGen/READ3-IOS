import Foundation

@MainActor
final class LibraryAutoUpdateCoordinator {
    private let repository: LibraryRepository
    private let libraryViewModel: LibraryViewModel
    private let settingsStore: LibraryUpdateSettingsStore
    private let notifier: any LibraryUpdateNotifying
    private let policy: LibraryAutoUpdatePolicy
    private var currentTask: Task<Void, Never>?
    private var currentTaskID: UUID?

    init(
        repository: LibraryRepository,
        libraryViewModel: LibraryViewModel,
        settingsStore: LibraryUpdateSettingsStore,
        notifier: any LibraryUpdateNotifying,
        policy: LibraryAutoUpdatePolicy = LibraryAutoUpdatePolicy()
    ) {
        self.repository = repository
        self.libraryViewModel = libraryViewModel
        self.settingsStore = settingsStore
        self.notifier = notifier
        self.policy = policy
    }

    var isRunning: Bool { currentTask != nil }

    func applicationDidBecomeActive(now: Date = Date()) {
        guard currentTask == nil else { return }
        let id = UUID()
        currentTaskID = id
        currentTask = Task { [weak self] in
            await self?.performCheckIfNeeded(now: now)
            guard self?.currentTaskID == id else { return }
            self?.currentTask = nil
            self?.currentTaskID = nil
        }
    }

    func checkIfNeeded(now: Date) async {
        guard currentTask == nil else {
            await currentTask?.value
            return
        }
        let task = Task { [weak self] in
            guard let self else { return }
            await self.performCheckIfNeeded(now: now)
        }
        let id = UUID()
        currentTaskID = id
        currentTask = task
        await task.value
        if currentTaskID == id {
            currentTask = nil
            currentTaskID = nil
        }
    }

    func applicationDidLeaveActiveState() {
        currentTask?.cancel()
        currentTask = nil
        currentTaskID = nil
        libraryViewModel.cancelRefreshes()
    }

    private func performCheckIfNeeded(now: Date) async {
        guard !repository.books.isEmpty,
              !libraryViewModel.isRefreshingAll,
              policy.shouldCheck(
                now: now,
                lastAutomaticCheckAt: settingsStore.lastAutomaticCheckAt,
                settings: settingsStore.settings
              ) else { return }

        let previousCheckAt = settingsStore.lastAutomaticCheckAt
        settingsStore.lastAutomaticCheckAt = now
        let summary = await libraryViewModel.refreshAll()
        if Task.isCancelled, summary.checkedCount == 0 {
            settingsStore.lastAutomaticCheckAt = previousCheckAt
            return
        }
        guard !Task.isCancelled else { return }
        guard settingsStore.settings.notificationEnabled, !summary.updates.isEmpty else { return }
        await notifier.notify(updates: summary.updates)
    }
}
