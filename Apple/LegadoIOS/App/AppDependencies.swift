import Foundation
import LegadoCore

struct AppDependencies {
    let sourceStore: BookSourceStore
    let libraryRepository: LibraryRepository
    let readerSettingsStore: ReaderSettingsStore
    let readerPaginator: any ReaderPaginating
    let searchService: any BookSearching
    let bookInfoService: any BookInfoLoading
    let tocService: any TOCLoading
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
        return AppDependencies(
            sourceStore: BookSourceStore(),
            libraryRepository: LibraryRepository(),
            readerSettingsStore: ReaderSettingsStore(),
            readerPaginator: TextKitReaderPaginator(),
            searchService: LegadoSearchService(
                runtime: BookSourceSearchRuntime(
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
            tocService: LegadoTOCService(
                runtime: BookSourceTOCRuntime(
                    httpClient: httpClient,
                    javaScriptExecutor: javaScriptExecutor
                )
            ),
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
        let cache = chapterContentCache
        Task {
            await cache.removeAll(for: ChapterCacheBookKey(
                sourceIdentity: book.sourceURL,
                bookIdentity: book.bookURL
            ))
        }
    }
}
