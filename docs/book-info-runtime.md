# Book-source BookInfo runtime

This analysis is pinned to Android Legado commit
`c043ea72fd2698d27a7dcbc0beb7844c572e544c`. The gitlink under
`Reference/READ3.0` was not initialized or modified; the commit was inspected in a
detached system-temporary checkout.

## Android call chain and request boundary

The production path is:

```text
SearchBook.toBook() / an existing Book
  -> WebBook.getBookInfoAwait(source, book, canReName)
  -> if book.infoHtml is nonempty: parse it directly
  -> otherwise AnalyzeUrl(book.bookUrl,
                         baseUrl=source.bookSourceUrl,
                         source headers, source, ruleData=book)
  -> getStrResponseAwait()
  -> BookInfo.analyzeBookInfo(baseUrl=book.bookUrl,
                             redirectUrl=response.url,
                             body=response.body)
  -> one AnalyzeRule(book, source)
  -> setContent(body).setBaseUrl(book.bookUrl).setRedirectUrl(response.url)
  -> ruleBookInfo.init, then field rules
  -> mutate and return the same Book
```

`bookUrl` normally comes from the selected search/explore result. Android also accepts an
already-created `Book`, so the value need not originate in search. A nonempty transient
`Book.infoHtml` bypasses networking and uses `bookUrl` as both base and redirect URL;
otherwise BookInfo always requests `book.bookUrl`. `AnalyzeUrl` resolves that request
against `bookSourceUrl`, applies source/login headers, URL options (including POST),
cookies, retry/proxy metadata, and its normal response decoding. READ3-IOS reuses
`RequestBuilder`, `HTTPClient`, and `TextDecoder`; login-check JavaScript, WebView, proxy
execution, and unsupported encodings remain outside this phase.

Android's OkHttp helper returns the final 4xx/5xx response after retries, so a non-null
body still enters BookInfo parsing. A transport failure or null body fails the operation.
The response URL is retained separately as `redirectUrl`; it is not substituted for the
canonical `book.bookUrl` or the rule `baseUrl`.

## `ruleBookInfo.init`

`init` is optional. Nil, empty, or whitespace-only means no initialization and every field
starts from the complete response body. A nonblank value is executed exactly once through
`AnalyzeRule.getElement`, then its raw result is passed to `AnalyzeRule.setContent`.

`getElement` supports the normal source-rule pipeline, including selector modes, regex
element extraction, JavaScript, templates, `@put`, and replacement. Its selector results
are structured:

- historical JSoup/CSS returns the complete `Elements` collection;
- JSONPath calls Jayway `getObject` and retains the returned map, list, scalar, or null;
- XPath returns the complete `List<JXNode>`;
- JavaScript retains its raw Rhino result until the next stage/API boundary.

No collection element is selected by BookInfo. A null final result reaches `setContent`
and throws Android's `AssertionError`; an empty but non-null collection is accepted and
later fields see that empty context. The same `AnalyzeRule` instance is used for init and
all fields, so `@put/@get` writes are shared. READ3-IOS represents both one node and a
multi-root context with the existing `RuleNode`; it does not serialize HTML/XPath roots or
JSON objects merely to feed later selectors.

Android may stringify/reparse JSoup `Elements` or an XPath list internally when switching
analyzer types. READ3-IOS deliberately retains equivalent roots directly for the supported
selector engines. This removes repeated parsing while preserving relative field lookup.
Direct structured-node-to-JavaScript remains explicitly unsupported because the current
JavaScript boundary has no DOM/map binding.

## Field order, input, and state

The fixed execution order is:

1. `name` via `getString`
2. `author` via `getString`
3. `kind` via `getStringList`, joined with `,`
4. `wordCount` via `getString`
5. `lastChapter` via `getString`
6. `intro` via `getString`
7. `coverUrl` via `getString`
8. `tocUrl` via `getString(..., isUrl=true)`

`updateTime` exists in `BookInfoRule` but is not read by this fixed BookInfo implementation.
`canReName` is a control rule/value, not a parsed result field: when the caller permits
renaming and the source value is nonblank, nonempty parsed name/author may replace values
already carried from search. Otherwise name/author only fill an empty value.

Every `getString`/`getStringList` invocation initializes its local `result` from the shared
initialized content. The previous field result is not the next field input. A rule's own
sequential stages update `result` normally. `@put/@get` storage does cross init and later
fields because all calls use one `AnalyzeRule` backed by the same Book; capture/result state
does not intentionally cross calls. READ3-IOS mirrors this with one fresh
`RuleExecutionContext` per BookInfo operation, resets `currentResult` and capture groups for
each field, and retains temporary variables across fields. Concurrent books therefore do
not share node owners, base URLs, results, captures, or temporary variables.

## Result mutation and normalization

Android applies `BookHelp.formatBookName`, `BookHelp.formatBookAuthor`,
`wordCountFormat`, and `HtmlFormatter.format` to name, author, word count, and intro.
`kind` is the rule list joined by comma; it is not split by the runtime. `lastChapter` is
display text only in this phase. Empty optional field results retain the values already
present on the Book. Name and author may also retain search values as described above.
There is no required-field exception for empty name, author, or toc URL.

`coverUrl` is updated only for a nonempty parsed value and is resolved against
`redirectUrl`. `tocUrl` is always assigned: `getString(isUrl=true)` resolves a nonblank
value against `redirectUrl`, while a blank value returns `baseUrl` (`book.bookUrl`). When
that final toc URL equals `book.bookUrl`, Android also caches the detail body as `tocHtml`;
TOC fetching/parsing is outside this phase. `bookUrl` itself is never overwritten by a
BookInfo rule and remains the canonical input value even after redirects.

The URL completion path accepts absolute, root-relative, path-relative, parent-relative,
scheme-relative, query-only, and fragment-only references. READ3-IOS uses the existing
`URLResolver`. Arbitrary schemes are retained consistently with the current resolver;
scheme security policy belongs at the later consumer boundary and full Android
`NetworkUtils` parity is not claimed.

## Error and capability policy

Name, author, init, and toc rule exceptions escape Android and fail BookInfo. Kind, word
count, last chapter, intro, and cover exceptions are caught, logged, and leave the prior
field value unchanged. A valid selector with no match is an empty result, not an error.
READ3-IOS exposes request-build, network, decoding, init, required-path field, optional
field diagnostics, structured input, and JavaScript-network capability categories while
preserving Android's optional-field continuation behavior.

Pure JavaScript works when an executor is injected and its direct input is scalar.
JavaScript directly receiving an HTML/JSON/XPath structured context fails with the existing
unsupported-structured-input capability. `java.ajax/get/post/head` production transport
remains **BLOCKED BY SYNC/ASYNC BOUNDARY** and returns an explicit capability error; it is
never replaced with an empty, null, or mocked production value.

## Swift runtime boundary

`BookSourceBookInfoRuntime.fetchBookInfo(source:book:)` is the async orchestration API:

```text
BookSearchResult.bookURL
  -> RequestBuilder (source header/cookies/options)
  -> HTTPClient.send
  -> HTTPResponse.text(TextDecoder)
  -> optional RuleNode init context
  -> ordered synchronous RuleExecutor field evaluation
  -> BookInfoResult
```

`BookInfoResult` keeps Legado URL/count values as strings and carries the search-derived
name, author, book URL, cover, intro, kind, word count, latest chapter, and source identity.
Parsed nonempty values update those fields according to Android's rules. `updateTime` is
not invented because the fixed runtime does not consume it. An in-memory content overload
is kept internal to tests/runtime orchestration rather than expanding the initial public API.
