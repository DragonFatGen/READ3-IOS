# Book-source search runtime

## Android reference behavior

This document is based on Android Legado commit
`c043ea72fd2698d27a7dcbc0beb7844c572e544c`, principally `WebBook`,
`AnalyzeUrl`, `BookList`, `AnalyzeRule`, and `SearchBook`.

The observable call chain is:

```text
WebBook.searchBookAwait(source, key, page)
  -> AnalyzeUrl(searchUrl, key, page, baseUrl=bookSourceUrl,
                source headers, source, fresh RuleData)
  -> getStrResponseAwait()
  -> BookList.analyzeBookList(baseUrl=response URL, body=response body, isSearch=true)
  -> AnalyzeRule.setContent(body).setBaseUrl(response URL)
  -> AnalyzeRule.getElements(ruleSearch.bookList)
  -> for each returned object: setContent(item), execute field rules
  -> SearchBook list
```

`key` is the supplied keyword. `page` defaults to 1. `pageSize` is not passed by this
Android search path. `AnalyzeUrl` expands the existing keyword/page placeholders and
`<first,second,last>` page alternatives. Source headers are passed before URL-option
headers, whose values override matching names.

The response body is decoded by Android's response decoding path and becomes
`AnalyzeRule.content`. The response request URL after redirects becomes both rule `baseUrl`
and `redirectUrl`; this is represented by `HTTPResponse.finalURL` in Swift.

## Book-list objects

`BookList` uses `AnalyzeRule.getElements`, not `getStringList`:

- HTML/JSoup returns `Elements`, whose items are `Element`.
- JSONPath returns a provider list containing maps, lists, or scalar values.
- XPath returns `List<JXNode>`; element nodes remain relative XPath roots.

For every item Android assigns that exact object to `AnalyzeRule.content`. Name, author,
URL, and other field rules therefore operate relative to the current item. Swift uses the
opaque node model described in `rule-node-context.md` and never serializes an item merely
to pass it between these stages.

## Field order and state

The fixed `BookList.getSearchItem` order is:

1. name
2. author
3. kind
4. wordCount
5. lastChapter
6. intro
7. coverUrl
8. bookUrl

One new `SearchBook` rule-data object is created per item from the request-level variable
snapshot. Consequently `@put/@get` can cross later fields within one item, but writes do not
leak into another item. Every `getString` call restarts `result` from the item content, so
the previous field's final result is not the next field's input. Capture groups likewise do
not intentionally cross field calls.

An empty formatted name filters the item. Author and book URL evaluation errors propagate
from Android and abort the search. Kind, word count, last chapter, intro, and cover errors
are logged and leave those optional fields empty. A blank book URL is replaced with the
response base URL; it is not filtered. Cover and book URLs are completed against that URL.

Android formats names/authors, word count, and introduction text. The Swift foundation
implements the stable name/author/word-count transformations and conservative HTML text
cleanup; exact Android `HtmlFormatter` whitespace behavior is a known difference.

## Swift runtime

`BookSourceSearchRuntime.search(source:keyword:page:)` is the asynchronous orchestration
boundary. It injects `HTTPClient`, `RequestBuilder`, selector execution, and optional pure
JavaScript execution. The flow is:

```text
BookSource.searchUrl
  -> RequestBuilder + RequestBuildContext
  -> HTTPClient.send
  -> HTTPResponse.text(TextDecoder)
  -> RuleNodeExecutor(bookList)
  -> fresh RuleExecutionContext per item
  -> RuleExecutor(field rules relative to RuleNode)
  -> [BookSearchResult]
```

Request option parsing, POST bodies, headers, cookies, pagination alternatives, retry
metadata, and URL construction stay in `RequestBuilder`. Response decoding stays in
`HTTPResponse`/`TextDecoder`; unsupported GBK-family encodings remain explicit errors.

`BookSearchResult` stores URL strings rather than `URL` because source rules may yield
dynamic or non-canonical values. `bookURL` and `coverURL` are resolved with `URLResolver`
against `HTTPResponse.finalURL`, including relative paths, scheme-relative URLs, queries,
and fragments.

An empty book-list returns an empty result. Android can fall back to its BookInfo path when
`bookUrlPattern` permits; BookInfo is deliberately outside this phase, so that fallback is
not reproduced. A leading `-` on the list rule reverses results; a leading `+` is ignored as
in Android.

## Errors and JavaScript capability

`BookSearchError` separates unsupported search, request construction, network, response
decoding, book-list execution, field execution, missing required name, structured-rule
capability, and production JavaScript network-host capability.

Pure field JavaScript can use the injected existing executor after a selector returns a
scalar, including `result` and `baseUrl`. JavaScript directly receiving a structured node is
unsupported. Rules that require `java.ajax/get/post/head` report
`unsupportedJavaScriptNetworkHost`; production network bridging remains blocked by the
documented synchronous/async boundary. No WebView, login, BookInfo, TOC, Content, database,
or UI behavior is added here.
