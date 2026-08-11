# Book-source TOC runtime

This analysis is pinned to Android Legado commit
`c043ea72fd2698d27a7dcbc0beb7844c572e544c`. `Reference/READ3.0` is read only.
The Swift phase described here stops after producing chapter metadata and never
requests a chapter URL.

## Android request and parsing chain

The normal detail-to-TOC path is:

```text
Book.tocUrl
  -> WebBook.getChapterListAwait(source, book)
  -> AnalyzeUrl(mUrl=tocUrl, baseUrl=bookUrl, source headers, source, book)
  -> getStrResponseAwait()
  -> BookChapterList.analyzeChapterList(baseUrl=tocUrl,
                                       redirectUrl=response URL,
                                       body=response body)
  -> AnalyzeRule(book, source).setContent(body).setBaseUrl(baseUrl)
  -> getElements(ruleToc.chapterList)
  -> getStringList(ruleToc.nextTocUrl, isUrl=true) on the page root
  -> per item: chapterName, chapterUrl, updateTime, isVolume, isVip, isPay
  -> reverse/deduplicate/index
  -> List<BookChapter>
```

`tocUrl` is the resolved value produced by BookInfo. `AnalyzeUrl` accepts the
complete Legado URL/options string, resolves it against `bookUrl`, applies source
headers and cookies, and can issue GET or POST. When Android retained `tocHtml`
because `tocUrl == bookUrl`, it parses that cached body without another request.
`BookInfoResult` has no cached body, so the Swift API always requests `tocURL`.

The response body is parsed even for a final 4xx/5xx response, as with the other
`StrResponse` paths. Transport failures escape. Response decoding follows the
shared decoder; unsupported GBK/GB2312/GB18030/Big5 remains a typed error. Android
can run `loginCheckJs` after the first request; login is outside this phase.

## Page root and chapter item semantics

`chapterList` calls `AnalyzeRule.getElements`, with `allInOne=true`. HTML returns
JSoup elements, JSONPath requires an array and returns its provider values, and
XPath returns `JXNode` values. A leading `-` is removed and requests reversed TOC
ordering; a leading `+` is removed and otherwise has no effect.

Swift reuses `RuleNode`, `RuleNodeCollection`, `RuleNodeExecutor`, and the current
HTML/JSON/XPath selector executors. Each chapter field starts from the exact item
node. It is not converted to outer HTML or compact JSON and reparsed for every
field. Direct structured-node JavaScript remains unsupported; JavaScript after a
selector has produced a scalar continues to work with an injected executor.

Android evaluates `nextTocUrl` on the full page content after `chapterList` and
before assigning any chapter item to the analyzer. It uses `getStringList(...,
isUrl=true)`, splits a returned string on newlines, resolves every nonempty value
against that page's redirect URL, removes duplicates in first-seen order, and
discards a URL equal to the current redirect URL.

The fixed per-item field order is:

1. `chapterName`
2. `chapterUrl`
3. `updateTime`
4. `isVolume`
5. if the name is nonempty, `isVip`
6. if the name is nonempty, `isPay`

Every field is `getString`; `chapterUrl` is not requested in this phase. A blank
name filters the item. A blank non-volume URL falls back to the page `baseUrl`. A
blank volume URL is synthesized as `title + itemIndex`; Android later recognizes
that sentinel and resolves it to the page redirect URL. Swift exposes the final
resolved URL directly. `isVolume`, `isVip`, and `isPay` use `String.isTrue`: blank
and `null` are false, as are case-insensitive `false`, `no`, `not`, and `0`; every
other nonblank value is true. `updateTime` becomes the chapter tag string.

Rule/JavaScript errors are not isolated per field and abort TOC parsing. An empty
final chapter list is an error. Android's debug logging indexes the first parsed
chapter when list elements existed, so an all-blank-name page can crash before its
later empty-list check; Swift reports a stable typed empty-TOC error instead.

## Pagination

Android has two distinct branches:

- zero next URLs: finish after the current page;
- one next URL: fetch it, parse its first next URL, and repeat until it is empty
  or already present in the visited URL list;
- multiple next URLs on the first page: fetch those pages concurrently in list
  order and parse chapters with `getNextUrl=false`; next links found on those
  pages are deliberately ignored.

The visited list initially contains the first response redirect URL, which also
prevents the common self-loop. Equality is exact string equality after URL
completion. Android has no maximum-page limit beyond cycle detection. Swift adds
a configurable finite page limit as a safety extension and reports a typed error
when it is exceeded.

On the initial page, `baseUrl` is the canonical `tocUrl`, while `redirectUrl` is
the response final URL. Chapter links and next links resolve against redirect URL;
rule JavaScript sees the page base URL. In Android's sequential one-link branch,
later pages use the requested next URL as both base and redirect URL even if the
request redirected. The multi-link branch uses each response's final URL as its
redirect URL. Swift preserves these observable bases. URL options remain attached
to request strings and are handled by `RequestBuilder`.

## Ordering and duplicates

Android's final ordering is intentionally indirect. With ordinary `chapterList`,
it reverses before URL-based `LinkedHashSet` deduplication and reverses again,
therefore the last duplicate URL wins while the visible order remains forward.
With a `-chapterList`, it deduplicates in encounter order and then reverses, so
the first duplicate wins. `Book.getReverseToc()` can apply a user preference on
top; Core has no persisted reading preference, so Swift implements its default
`false` behavior. A leading `+` produces normal forward behavior.

Android `BookChapter.equals/hashCode` uses only the raw chapter URL. Swift applies
the same deduplication key before exposing resolved URLs, so distinct relative
spellings that resolve to the same absolute URL are not accidentally merged.
Final zero-based indices are assigned only after ordering and deduplication.

## Variable, result, and concurrency context

Android constructs one `AnalyzeRule` per page backed by the same mutable `Book`.
Before item iteration, `chapterList` and `nextTocUrl` `@put` writes go to the book
and are visible on later pages. Each item then assigns a fresh `BookChapter` to
`AnalyzeRule.chapter`; field writes go to that chapter, are visible to later fields
of the same item, and do not leak to another item. Each field restarts `result`
from the item node; the previous field result is not the next field input.

Swift represents this with one book-scoped page context per `fetchTOC` and a fresh
item context seeded from the page variables for every chapter. Pages share the
book-scoped values; items share values only across their own ordered fields.
Separate `fetchTOC` calls own separate contexts, node graphs, bases, captures, and
variables, so concurrent books cannot pollute one another.

## Swift result and capability boundary

The asynchronous API is:

```swift
BookSourceTOCRuntime.fetchTOC(source:book:) async throws -> [BookChapterResult]
```

It injects `HTTPClient`, `RequestBuilder`, `RuleNodeSelectorExecutor`, optional
`RuleJavaScriptExecutor`, `TextDecoder`, and a maximum-page safety limit.
`BookChapterResult` retains the Android-observable chapter title/name, resolved URL,
volume/VIP/pay flags, update tag, final index, parent book URL, and source URL. URLs
remain strings. A separate stored base URL is unnecessary because the public chapter
URL is already completed for the future Content runtime.

Production `java.ajax/get/post/head` remains **BLOCKED BY SYNC/ASYNC BOUNDARY** and
returns the explicit TOC capability error. WebView, `webJs`, login, persistence,
Content runtime, UI, and database behavior are not implemented.
