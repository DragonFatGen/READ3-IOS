import LegadoCore

struct AppDependencies {
    let sourceStore: BookSourceStore
    let searchService: any BookSearching
    let bookInfoService: any BookInfoLoading
    let tocService: any TOCLoading
    let contentService: any ChapterContentLoading

    @MainActor
    static func live() -> AppDependencies {
        // Every runtime receives the same client value. URLSessionHTTPClient is
        // currently stateless and creates ephemeral requests; keeping this
        // composition root makes a future shared session/cookie implementation
        // a single lifecycle change instead of a per-feature change.
        let httpClient = URLSessionHTTPClient()
        let javaScriptExecutor = JavaScriptCoreRuleJavaScriptExecutor()
        return AppDependencies(
            sourceStore: BookSourceStore(),
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
            contentService: LegadoChapterContentService(
                runtime: BookSourceContentRuntime(
                    httpClient: httpClient,
                    javaScriptExecutor: javaScriptExecutor
                )
            )
        )
    }
}
