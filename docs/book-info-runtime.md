# Book-source book-info runtime

This analysis is pinned to Android Legado commit
`c043ea72fd2698d27a7dcbc0beb7844c572e544c`. The reference tree was read only.
The Swift implementation described below deliberately stops at a resolved `tocURL`.

## Android call chain and request boundary

The normal search-to-detail path is:

```text
SearchBook.toBook()
  -> WebBook.getBookInfoAwait(source, book, canReName=true)
  -> AnalyzeUrl(mUrl=book.bookUrl, baseUrl=source.bookSourceUrl,
                source headers, source, ruleData=book)
  -> getStrResponseAwait()
  -> BookInfo.analyzeBookInfo(baseUrl=book.bookUrl,
                             redirectUrl=StrResponse.url,
                             body=StrResponse.body)
  -> one AnalyzeRule(book, source)
  -> setContent(body).setBaseUrl(book.bookUrl).setRedirectUrl(response URL)
  -> ruleBookInfo.init, then field rules
  -> mutate and return the same Book
```

`bookUrl` originates in the selected `SearchBook` (normally the resolved
`ruleSearch.bookUrl`) and is copied unchanged by `SearchBook.toBook`. Detail does not
have a rule that replaces it. `AnalyzeUrl` accepts the complete Legado URL string, so
detail URLs can carry URL options, including POST options. It resolves a relative
request URL against `bookSourceUrl`, merges the source header and option headers, loads
source-scoped cookies, and uses the normal retry/proxy/redirect request path.

Detail normally requests `book.bookUrl`, but not unconditionally. If `Book.infoHtml` is
nonempty, Android parses that body directly with both `baseUrl` and `redirectUrl` equal
to `book.bookUrl`. `BookSearchResult` in Core has no cached HTML field, so the initial
Swift public search-result API always performs the request; cached-body orchestration is
not invented in this phase.

OkHttp retries unsuccessful statuses and returns the last response. `StrResponse` uses
the response body even for 4xx/5xx, or the status message when no body exists. BookInfo
therefore still parses a 404/500 body. Transport failures escape. Decoding removes a
UTF-8 BOM, then uses Content-Type charset, then Android detection. Swift delegates to
`TextDecoder`; GBK/GB2312/GB18030/Big5 remain typed unsupported errors.

`loginCheckJs` may replace the `StrResponse` after the request in Android. Login and
WebView behavior are outside this phase.

## `ruleBookInfo.init`

`init` is optional. A null, empty, or whitespace-only value is skipped, leaving the
entire response body as `AnalyzeRule.content`. Otherwise Android executes exactly:

```kotlin
analyzeRule.setContent(analyzeRule.getElement(infoRule.init))
```

It uses `AnalyzeRule.getElement`, not `getString` or `getElements`. `getElement` parses
the rule with `allInOne=true`, runs every source-rule stage, executes `@put` before its
stage, permits JavaScript, and preserves the returned object:

- historical JSoup/CSS returns an `Elements` collection, including all matches;
- JSONPath calls `getObject` and returns the selected map, list, or scalar without
  stringification;
- XPath calls `getElements` and returns its complete `List<JXNode>`;
- all-in-one regex returns its element result;
- JavaScript returns the raw Rhino result.

There is no “take the first init match” step. A collection remains the context collection.
`setContent` rejects null with an assertion, so a failed/null init aborts detail parsing.
An empty but non-null collection is accepted and later selectors see an empty context.
An empty JavaScript string is also accepted. The same `AnalyzeRule` instance is retained,
its selector adapters are invalidated, and later fields start from that exact init object.
HTML elements, JSON objects, and XPath element nodes are therefore relative roots rather
than serialized response fragments.

Swift reuses `RuleNode`, `RuleNodeCollection`, `RuleNodeExecutor`, and the existing
selector adapter. It does not introduce a BookInfo-specific node family. Structured
nodes are retained from init to every field; HTML and JSON are not converted to outer
HTML/compact JSON and reparsed per field.

## Field order, state, and result

The fixed Android order is:

1. name
2. author
3. kind
4. wordCount
5. lastChapter
6. intro
7. coverUrl
8. tocUrl

`updateTime` exists in `BookInfoRule` but is not read by this BookInfo implementation.
`canReName` is not an extracted result field: it enables replacing a nonempty existing
name/author when the caller also permits rename.

One `AnalyzeRule` and the same book-backed variable store are used for init and every
field. Consequently `@put/@get` writes are visible to later fields in the order above.
Each `getString`/`getStringList` call independently initializes its local `result` from
the current analyzer content (the init context, or the response root when init was
skipped). The previous field's returned string is not the next field's input. JavaScript
`result` is the object entering that JavaScript stage: initially the field's current
content, or the scalar/node result of an earlier stage in the same rule.

Each Swift fetch creates a fresh `RuleExecutionContext`; concurrent books do not share
temporary variables, capture groups, current result, node ownership, or base URL. Core
does not currently persist Android book variables, so only variables written during the
one detail execution are shared across its fields.

## Field behavior

- `name`: `getString`, then Android book-name formatting. A nonempty value replaces the
  existing name only when the existing name is empty or rename is enabled by both caller
  and nonblank `canReName`. Rule errors propagate.
- `author`: same policy using author formatting. Rule errors propagate.
- `kind`: `getStringList`, joined with `,` without splitting an extracted scalar.
  Errors are logged and the existing value is retained.
- `wordCount`: `getString`, then `wordCountFormat`; it remains a string such as `123万字`.
  Errors retain the existing value.
- `lastChapter`: `getString`; it only updates display metadata and does not load TOC.
  Errors retain the existing value.
- `intro`: `getString`, then `HtmlFormatter.format`. Cleanup belongs to that established
  Android formatter, not arbitrary runtime trimming. Errors retain the existing value.
- `coverUrl`: `getString`; a nonempty value is completed against `redirectUrl`. Errors or
  empty results retain the existing cover.
- `tocUrl`: `getString(..., isUrl=true)`. A nonblank value is completed against
  `redirectUrl`; blank resolves/falls back to the original `baseUrl` (`book.bookUrl`). If
  the final TOC URL equals that original base URL, Android stores the response body in
  `book.tocHtml` for the next stage. The Swift result stores the resolved URL only and
  does not start TOC parsing.

Name, author, and TOC are not guarded by per-field `try/catch`; invalid rules or
JavaScript errors abort BookInfo. Optional kind/word-count/last-chapter/intro/cover
errors are isolated and retain the search value. Empty name/author are allowed and
retain their existing search values. Empty TOC is not an error; it falls back to the
original book URL. There is no independent required-field validation.

## URL bases

Android intentionally keeps two URL concepts:

- `AnalyzeRule.baseUrl` is always the incoming canonical `book.bookUrl`, even after a
  redirect. It is visible to JavaScript and is the blank-TOC fallback.
- `AnalyzeRule.redirectUrl` is `StrResponse.url` (the final network request URL). It is
  used by `isUrl=true` and explicitly by cover completion.

Thus a redirect changes relative `coverUrl`/`tocUrl` resolution but does not replace the
result's `bookURL`. Absolute, root-relative, path-relative, parent-relative,
scheme-relative, query, and fragment references follow the shared URL resolver. The
Android helper accepts absolute non-HTTP schemes as strings; this phase does not add a
new security policy beyond existing request and URL-resolution behavior.

## Swift API and capability boundary

The asynchronous orchestration API is:

```swift
BookSourceBookInfoRuntime.fetchBookInfo(source:book:) async throws -> BookInfoResult
```

It injects `HTTPClient`, `RequestBuilder`, `RuleNodeSelectorExecutor`, optional
`RuleJavaScriptExecutor`, and `TextDecoder`. Request building, source headers, cookies,
URL options, POST, retries, and proxy metadata stay in `RequestBuilder`; transport stays
in `HTTPClient`; response decoding stays in `TextDecoder`; rule execution remains
synchronous.

`BookInfoResult` contains the observable detail/search state needed by the next stage:
name, author, canonical book URL, resolved cover URL, intro, kind, word count, last
chapter, resolved TOC URL, and source identity/order metadata. URLs remain strings for
Legado compatibility. `updateTime`, cached HTML, UI state, persistence state, and chapter
models are not added.

Pure JavaScript works when the injected executor can consume the scalar input at that
stage. JavaScript whose direct input is an HTML/JSON/XPath structured init context remains
an explicit `unsupported structured JavaScript input` capability error; silently passing
outer HTML or compact JSON would be false compatibility. `java.ajax/get/post/head` remain
**BLOCKED BY SYNC/ASYNC BOUNDARY** and produce the dedicated unsupported-network-host
error. No production bridge, WebView, `webJs`, login, TOC, or content runtime is added.
