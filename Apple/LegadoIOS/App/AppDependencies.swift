import Foundation
import LegadoCore

struct AppDependencies {
    let sourceStore: BookSourceStore
    let libraryRepository: LibraryRepository
    let readerSettingsStore: ReaderSettingsStore
    let readerSpeechSettingsStore: ReaderSpeechSettingsStore
    let readerSpeechController: ReaderSpeechController
    let bookmarkRepository: BookmarkRepository
    let readerPaginator: any ReaderPaginating
    let searchService: any BookSearching
    let exploreService: any BookExploring
    let bookInfoService: any BookInfoLoading
    let tocService: any TOCLoading
    let bookUpdateChecker: any BookUpdateChecking
    let libraryViewModel: LibraryViewModel
    let libraryUpdateSettingsStore: LibraryUpdateSettingsStore
    let libraryUpdateNotifier: any LibraryUpdateNotifying
    let libraryAutoUpdateCoordinator: LibraryAutoUpdateCoordinator
    let chapterContentCache: any ChapterContentCache
    let contentService: any ChapterContentLoading

    @MainActor
    static func live() -> AppDependencies {
        // Every runtime receives the same client value. URLSessionHTTPClient is
        // currently stateless and creates ephemeral requests; keeping this
        // composition root makes a future shared session/cookie implementation
        // a single lifecycle change instead of a per-feature change.
        let httpClient = URLSessionHTTPClient()
        let javaScriptExecutor = JavaScriptCoreRuleJavaScriptExecutor()
        let cacheDirectory = FileManager.default.urls(
            for: .cachesDirectory,
            in: .userDomainMask
        )[0].appendingPathComponent("ChapterContent", isDirectory: true)
        let chapterContentCache = FileChapterContentCache(directory: cacheDirectory)
        let productionContentService = LegadoChapterContentService(
            runtime: BookSourceContentRuntime(
                httpClient: httpClient,
                javaScriptExecutor: javaScriptExecutor
            )
        )
        let tocService = LegadoTOCService(
            runtime: BookSourceTOCRuntime(
                httpClient: httpClient,
                javaScriptExecutor: javaScriptExecutor
            )
        )
        let sourceStore = BookSourceStore()
        let libraryRepository = LibraryRepository()
        let bookUpdateChecker = TOCBookUpdateChecker(tocService: tocService)
        let libraryViewModel = LibraryViewModel(
            repository: libraryRepository,
            sourceStore: sourceStore,
            checker: bookUpdateChecker
        )
        let updateSettingsStore = LibraryUpdateSettingsStore()
        let updateNotifier = UserNotificationLibraryUpdateNotifier()
        let updateCoordinator = LibraryAutoUpdateCoordinator(
            repository: libraryRepository,
            libraryViewModel: libraryViewModel,
            settingsStore: updateSettingsStore,
            notifier: updateNotifier
        )
        let speechSettingsStore = ReaderSpeechSettingsStore()
        let speechController = ReaderSpeechController(
            synthesizer: AppleReaderSpeechSynthesizer(),
            audioSession: AppleReaderAudioSessionManager(),
            remoteCommands: AppleReaderRemoteCommandManager(),
            settingsStore: speechSettingsStore
        )
        return AppDependencies(
            sourceStore: sourceStore,
            libraryRepository: libraryRepository,
            readerSettingsStore: ReaderSettingsStore(),
            readerSpeechSettingsStore: speechSettingsStore,
            readerSpeechController: speechController,
            bookmarkRepository: BookmarkRepository(),
            readerPaginator: TextKitReaderPaginator(),
            searchService: LegadoSearchService(
                runtime: BookSourceSearchRuntime(
                    httpClient: httpClient,
                    javaScriptExecutor: javaScriptExecutor
                )
            ),
            exploreService: LegadoExploreService(
                parser: ExploreURLParser(javaScriptExecutor: javaScriptExecutor),
                runtime: BookSourceExploreRuntime(
                    httpClient: httpClient,
                    javaScriptExecutor: javaScriptExecutor
                )
            ),
            bookInfoService: LegadoBookInfoService(
                runtime: BookSourceBookInfoRuntime(
                    httpClient: httpClient,
                    javaScriptExecutor: javaScriptExecutor
                )
            ),
            tocService: tocService,
            bookUpdateChecker: bookUpdateChecker,
            libraryViewModel: libraryViewModel,
            libraryUpdateSettingsStore: updateSettingsStore,
            libraryUpdateNotifier: updateNotifier,
            libraryAutoUpdateCoordinator: updateCoordinator,
            chapterContentCache: chapterContentCache,
            contentService: CachedContentService(
                cache: chapterContentCache,
                upstream: productionContentService
            )
        )
    }

    @MainActor
    func removeFromLibrary(_ book: LibraryBook) {
        libraryRepository.remove(bookID: book.id)
        bookmarkRepository.removeAll(for: book.id)
        let cache = chapterContentCache
        Task {
            await cache.removeAll(for: ChapterCacheBookKey(
                sourceIdentity: book.sourceURL,
                bookIdentity: book.bookURL
            ))
        }
    }
}
