# BookSource Explore Runtime

## Android reference

This implementation was derived from Android Legado commit
`c043ea72fd2698d27a7dcbc0beb7844c572e544c` rather than from field names alone.
The relevant call chain is:

1. `BookSource.exploreKinds` parses `BookSource.exploreUrl` into `ExploreKind` values.
2. `ExploreAdapter` displays those values in their original order. A kind without a
   URL is rendered as non-clickable text; it is a visual header, not a nested node.
3. Selecting a kind passes its URL through `ExploreFragment` to
   `ExploreShowActivity` / `ExploreShowViewModel`.
4. `ExploreShowViewModel` starts at page 1 and calls
   `WebBook.exploreBook(scope, source, selectedURL, page)`.
5. `WebBook.exploreBookAwait` creates a fresh `RuleData`, constructs `AnalyzeUrl`
   with the selected URL, page, source base URL, and source headers, then performs
   the request.
6. The response body and final response URL are passed to
   `BookList.analyzeBookList(..., isSearch = false)`.
7. `BookList` uses `ruleExplore` when its `bookList` is nonblank; otherwise the
   complete `ruleSearch` list definition is used. It returns `SearchBook`, the same
   model returned by search.
8. On a successful load Android increments the caller-owned page. The activity
   declares no-more-data for an empty page or when both the first and last returned
   books already exist in the adapter.

The Core equivalent is `ExploreURLParser` plus `BookSourceExploreRuntime`. Explore
and Search share `BookListParser` and both return `BookSearchResult`.

## `exploreUrl` category syntax

Android supports two category representations:

- Plain text entries separated by one or more `&&` tokens or newlines. Each entry
  is split on `::`; element zero is the title and element one, when present, is the
  URL. Extra split elements are ignored by Android.
- A JSON array of `ExploreKind` objects containing `title`, optional `url`, and an
  optional `style` object. Style keys are Android Flexbox names such as
  `layout_flexGrow` and use Android's defaults when omitted.

An entire category definition beginning with `@js:` or `<js>` is evaluated before
either representation is parsed. Android caches that generated string per source
until the user refreshes it. Core accepts an injected `RuleJavaScriptExecutor` but
does not own an application cache, so callers that need Android's refresh policy
must cache the parsed category value outside LegadoCore.

The data is a flat ordered list. Entries without URLs act as group labels. The
fixed Android implementation has no recursive or multi-level category tree.

## Pagination and request construction

Pagination belongs to the caller. `BookSourceExploreRuntime.explore` accepts a
one-based `page` and performs exactly one request; it does not invent an infinite
scroll or next-page protocol. `RequestBuilder` applies Android `AnalyzeUrl` rules:

- `{{page}}` and `@get:{page}` read the requested page.
- `<first,second,last>` selects the one-based entry and repeats the final entry for
  later pages.
- URL JavaScript runs before URL option parsing and request execution.
- `{{...}}` expressions that are not direct known-variable substitutions use the
  injected JavaScript executor.
- URL-option `js` runs after the initial URL is made absolute and may replace it.
- URL `@put` writes survive request construction and are passed into the book-list
  rule context, matching the shared Android `RuleData` lifetime.
- GET query fields and form POST bodies retain the existing charset-aware request
  encoding, source/option header precedence, cookies, redirect policy, and retry
  metadata.

Android's UI, not `WebBook.exploreBookAwait`, decides that pagination is exhausted
from an empty page or duplicate boundary items. Core therefore returns the parsed
page unchanged and leaves that policy to a future UI/caller.

## Response and book-list semantics

`BookListParser` receives the response's final URL. This matches Android passing
`StrResponse.url` after redirects and using it as `AnalyzeRule.baseUrl` and
`redirectUrl` for list parsing. Both relative `bookUrl` and `coverUrl` are resolved
against that final URL. A blank `bookUrl` falls back to the final URL.

The field evaluation order matches Android `BookList.getSearchItem`:

1. name;
2. author;
3. kind;
4. word count;
5. last chapter;
6. intro;
7. cover URL;
8. book URL.

Items with blank names are filtered. Optional field failures are recoverable, as
in Android. `updateTime` exists in the source model but the fixed Android
`BookList.getSearchItem` does not read it. A leading `-` on `bookList` reverses the
result and a leading `+` is ignored. HTML/JSoup, CSS, JSONPath, XPath, regex,
templates, `@put/@get`, and injected JavaScript all use the existing rule engine.
HTTP status alone does not discard a body, so a parseable 404 body can still yield
books.

Each Explore call creates independent request and rule contexts. Each item gets a
fresh variable context initialized from URL-stage variables, so field writes flow
forward within one item without contaminating another item or concurrent request.

## JavaScript context and unsupported boundaries

AnalyzeUrl URL JavaScript on Android binds `java`, `baseUrl`, `cookie`, `cache`,
`page`, `key`, speech values, `book`, `source`, and `result`. Explore supplies page
and source but no search keyword. AnalyzeRule field JavaScript instead binds its
current result, base URL, source, book/chapter data, and content-related values.

Core exposes only its platform-neutral `JavaScriptExecutionContext` snapshot:
result, base URL, source identity/header, source variables, and temporary variables
including page during URL construction. Book-list field execution receives only
variables persisted by URL-stage `@put`, matching Android's shared `RuleData`; page
is not otherwise injected into `AnalyzeRule` fields. Core deliberately does not
expose Android globals, mutable caches, or arbitrary native APIs.

## iOS Explore presentation compatibility

The iOS application caches parsed categories in `ExploreViewModel`, keyed by
`bookSourceUrl`, for the lifetime of that view model. Switching sources and then
returning does not execute category JavaScript again. Pull-to-refresh reloads only
the current book list; the toolbar's explicit category refresh clears only the
current source's category cache.

Pagination follows `ExploreShowActivity.upData`: an empty page stops loading, as
does a page whose first and last `SearchBook` are both already present. Android's
`SearchBook.equals` compares only `bookUrl`, so iOS uses `BookSearchResult.bookURL`
for the same boundary check. Otherwise the complete page is appended in returned
order, including individual duplicates.

The category list remains flat and ordered. Items without a URL are noninteractive
headings. SwiftUI honors `layout_wrapBefore` and near-full-width
`layout_flexBasisPercent` as row breaks. It intentionally does not emulate Android
Flexbox's `layout_flexGrow`, `layout_flexShrink`, or `layout_alignSelf`; adaptive
grid sizing is used so long localized titles wrap safely.

The following remain outside this phase:

- production `java.ajax`, `java.get`, `java.post`, and `java.head` (reported as an
  explicit unsupported capability rather than synchronously waiting on network);
- WebView, `webJs`, source login UI, and `loginCheckJs`;
- cross-launch persistence of generated categories;
- cookie-backed persistent user accounts;
- pixel-identical Android Flexbox layout.
