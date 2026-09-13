import Foundation
import LegadoCore
import XCTest
@testable import LegadoIOS

/// Exercises the app's stores, view models and production Core adapters, without
/// launching SwiftUI or contacting a website. All text below is synthetic.
@MainActor
final class OfflineReadingFlowTests: XCTestCase {
    func testImportSearchDetailShelfTOCContentAndReopen() async throws {
        let suite = "OfflineReadingFlow.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let sources = BookSourceStore(defaults: defaults)
        sources.importSources(from: Data(Self.sourceJSON.utf8))
        XCTAssertNil(sources.errorMessage)
        XCTAssertEqual(sources.allSources.count, 1)
        let source = try XCTUnwrap(BookSourceStore(defaults: defaults).enabledSources.first)
        let client = OfflineReadingHTTPClient()
        let search = SearchViewModel(source: testSource(), service: LegadoSearchService(
            runtime: BookSourceSearchRuntime(httpClient: client)
        ))
        search.selectSource(source)
        search.query = "合成"
        search.search()
        await waitUntil { !search.isLoading }
        XCTAssertNil(search.errorMessage)
        let result = try XCTUnwrap(search.results.first)
        XCTAssertEqual(result.sourceURL, source.bookSourceUrl)
        XCTAssertEqual(result.bookURL, "https://reading.invalid/book/one")

        let detail = BookDetailViewModel(source: source, searchResult: result,
            service: LegadoBookInfoService(runtime: BookSourceBookInfoRuntime(httpClient: client)))
        await detail.loadIfNeeded()
        let info = try XCTUnwrap(detail.bookInfo)
        XCTAssertEqual(info.name, "合成测试书")
        XCTAssertEqual(info.tocURL, "https://reading.invalid/toc")
        let library = LibraryRepository(defaults: defaults)
        library.add(source: source, bookInfo: info)
        library.add(source: source, bookInfo: info)
        XCTAssertEqual(library.books.count, 1)
        let bookID = try XCTUnwrap(library.books.first?.id)

        let tocService = LegadoTOCService(runtime: BookSourceTOCRuntime(httpClient: client))
        let toc = TOCViewModel(source: source, book: info, service: tocService)
        await toc.loadIfNeeded()
        XCTAssertNil(toc.errorMessage)
        XCTAssertEqual(toc.chapters.map(\.name), ["测试章一", "测试章二"])
        let secondChapter = try XCTUnwrap(toc.chapters.dropFirst().first)
        let contentService = LegadoChapterContentService(
            runtime: BookSourceContentRuntime(httpClient: client)
        )
        let reader = ReaderViewModel(source: source, book: info, libraryBookID: bookID,
            chapters: toc.chapters, initialChapterIndex: 0, contentService: contentService,
            progressStore: library)
        defer { reader.cancel() }
        reader.loadInitialChapter()
        await waitUntil { reader.content != nil }
        XCTAssertEqual(reader.content?.content, "合成段落一。")
        reader.goToNextChapter()
        await waitUntil { reader.content?.chapterURL == secondChapter.url }
        XCTAssertEqual(reader.content?.content, "合成段落二。")
        reader.updateProgress(0.63)
        reader.cancel() // The ordinary reader-disappear path flushes progress.
        library.add(source: source, bookInfo: info)
        XCTAssertEqual(library.books.count, 1)
        XCTAssertEqual(library.books.first?.progress?.chapterProgress, 0.63)

        // New storage and model instances simulate reopening persisted app data.
        // This does not simulate an OS process termination or a real viewport.
        let reopenedDefaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        let reopenedLibrary = LibraryRepository(defaults: reopenedDefaults)
        let savedBook = try XCTUnwrap(reopenedLibrary.books.first)
        XCTAssertEqual(savedBook.id, bookID)
        XCTAssertEqual(savedBook.progress?.lastChapterURL, secondChapter.url)
        XCTAssertEqual(savedBook.progress?.lastChapterIndex, 1)
        XCTAssertEqual(savedBook.progress?.chapterCount, 2)
        let reopenedTOC = TOCViewModel(source: savedBook.source, book: savedBook.bookInfo, service: tocService)
        await reopenedTOC.loadIfNeeded()
        let index = try XCTUnwrap(reopenedTOC.chapters.firstIndex {
            $0.url == savedBook.progress?.lastChapterURL
        })
        let reopenedReader = ReaderViewModel(source: savedBook.source, book: savedBook.bookInfo,
            libraryBookID: bookID, chapters: reopenedTOC.chapters, initialChapterIndex: index,
            contentService: contentService, progressStore: reopenedLibrary)
        defer { reopenedReader.cancel() }
        XCTAssertEqual(reopenedReader.currentChapterIndex, 1)
        XCTAssertEqual(reopenedReader.consumeRestorationProgress(), 0.63)
        XCTAssertNil(reopenedReader.consumeRestorationProgress())
        reopenedReader.loadInitialChapter()
        await waitUntil { reopenedReader.content != nil }
        XCTAssertEqual(reopenedReader.content?.content, "合成段落二。")
        let requests = await client.requests
        XCTAssertTrue(requests.allSatisfy { $0.url.host == "reading.invalid" })
        XCTAssertEqual(requests.first?.method, .post)
        XCTAssertEqual(requests.first?.body, Data("searchkey=%E5%90%88%E6%88%90".utf8))
        XCTAssertTrue(requests.contains { $0.url.path == "/book/one" })
        XCTAssertTrue(requests.contains { $0.url.path == "/toc" })
    }

    private func waitUntil(_ condition: @MainActor () -> Bool) async {
        for _ in 0..<500 {
            if condition() { return }
            try? await Task.sleep(for: .milliseconds(2))
        }
        XCTFail("Timed out waiting for offline reading flow")
    }

    private static let sourceJSON = #"""
    {
      "bookSourceUrl": "https://reading.invalid",
      "bookSourceName": "离线合成书源",
      "searchUrl": "/search,{\"method\":\"POST\",\"body\":\"searchkey={{key}}\"}",
      "ruleSearch": {
        "bookList": "@CSS:article",
        "name": "@CSS:a@text",
        "author": "@CSS:span@text",
        "bookUrl": "@CSS:a@href"
      },
      "ruleBookInfo": {
        "name": "@CSS:h1@text",
        "author": "@CSS:span@text",
        "tocUrl": "@CSS:a@href"
      },
      "ruleToc": {
        "chapterList": "@CSS:a",
        "chapterName": "text",
        "chapterUrl": "href"
      },
      "ruleContent": { "content": "@CSS:p@text" }
    }
    """#
}

private actor OfflineReadingHTTPClient: HTTPClient {
    private(set) var requests: [HTTPRequest] = []

    func send(_ request: HTTPRequest) async throws -> HTTPResponse {
        requests.append(request)
        guard request.url.host == "reading.invalid" else { throw ViewModelTestError.expected }
        let html: String
        switch request.url.path {
        case "/search":
            html = #"<article><a href="/book/one">合成测试书</a><span>合成作者</span></article>"#
        case "/book/one":
            html = #"<h1>合成测试书</h1><span>合成作者</span><a href="/toc">目录</a>"#
        case "/toc":
            html = #"<a href="/chapter/one">测试章一</a><a href="/chapter/two">测试章二</a>"#
        case "/chapter/one": html = "<p>合成段落一。</p>"
        case "/chapter/two": html = "<p>合成段落二。</p>"
        default: throw ViewModelTestError.expected
        }
        return HTTPResponse(statusCode: 200, headers: HTTPHeaders(["Content-Type": "text/html; charset=utf-8"]),
            data: Data(html.utf8), finalURL: request.url)
    }
}
