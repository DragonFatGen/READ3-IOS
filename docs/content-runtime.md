# Book-source content runtime

## Compatibility baseline

This document records observable content behavior from Android Legado commit
`c043ea72fd2698d27a7dcbc0beb7844c572e544c`. The primary call sites are
`WebBook.getContentAwait`, `BookContent.analyzeContent`, `ContentRule`,
`AnalyzeUrl`, `AnalyzeRule`, and `RuleAnalyzer`.

The Swift implementation is a native runtime built on the existing
`RequestBuilder`, `HTTPClient`, `TextDecoder`, `URLResolver`, `RuleParser`,
`RuleExecutor`, `RuleNodeExecutor`, and selector engines. It does not reproduce the
Android object graph or Android persistence.

## Android request and analysis chain

`WebBook.getContentAwait` first checks two non-network exits:

1. A null or empty `ruleContent.content` returns `BookChapter.url` unchanged.
2. A synthetic volume whose URL starts with its title returns the chapter tag.

For ordinary content, `BookChapter.getAbsoluteURL()` resolves the chapter URL
against the chapter base URL while preserving the trailing Legado URL option
object. `AnalyzeUrl` then expands URL JavaScript/templates and variables, parses the
option object, applies method, headers, body, charset, retry, proxy, and web
options, and performs the request. The book is its rule-data object and the chapter
is separately available to URL JavaScript. `webJs` and `sourceRegex` are passed to
the request path; `loginCheckJs` can transform the response afterward.

The resulting response enters `BookContent.analyzeContent` with two URL values:

- `baseUrl` is the requested absolute chapter or content-page URL, including its
  URL options.
- `redirectUrl` is `StrResponse.url`, derived from the final OkHttp response request
  URL.

Each page creates a new `AnalyzeRule(book, source)`, calls
`setContent(body, baseUrl)`, calls `setRedirectUrl(redirectUrl)`, and then attaches
the same chapter and next-chapter boundary.

OkHttp retries non-success responses but ultimately returns the final response even
when it is 4xx/5xx. `newCallStrResponse` decodes and exposes that response body, so
the content rules continue to parse an HTTP error body. Only transport failure or
an absent/unreadable body prevents normal parsing.

## `content` rule semantics

`ruleContent.content` is passed to `AnalyzeRule.getString`, not `getStringList`,
`getElement`, or `getElements`. It therefore uses the scalar source-rule pipeline:

1. Start every call from the page response root.
2. Run selector/JSONPath/XPath stages as scalar extraction.
3. Run `##regex##replacement` stages in source-rule order.
4. Expand `@get`, capture references, and `{{...}}`.
5. Run JavaScript stages with the preceding scalar as `result`.
6. Convert a null result to `""` and HTML-entity-unescape the final string.

A selector followed by regex, template, or JavaScript remains a scalar pipeline.
Structured DOM/JSON/XPath nodes are not serialized and reparsed to make direct
structured JavaScript work. Such a boundary remains explicitly unsupported.

After extraction, every page is passed through
`HtmlFormatter.formatKeepImg(content, redirectUrl)`. That formatter:

- changes `&nbsp;`, `&ensp;`, and `&emsp;` to ordinary spaces;
- removes `&thinsp;`, `&zwnj;`, and `&zwj;`;
- changes block tags (`div`, `p`, `br`, `hr`, headings, `article`, `dd`, and `dl`)
  to line breaks;
- removes comments and all remaining non-image tags;
- normalizes runs around line breaks;
- prefixes each resulting paragraph with two ideographic spaces (`　　`);
- retains `<img>` tags in a canonical `<img src="...">` form and resolves image
  URLs against the page redirect URL.

The runtime does not add reader-oriented typography beyond this Android formatter.

`ContentRule.replaceRegex` is not a raw regular expression field. Android calls
`AnalyzeRule.getString(replaceRegex, mergedContent)` after all pages have been
formatted and joined. It is therefore a complete source rule evaluated with the
merged content as its temporary root; a common value such as
`##pattern##replacement` performs final purification, while templates and
JavaScript can also participate.

If the final, purified content is blank, Android throws `ContentEmptyException`.

## `nextContentUrl` and pagination

The same per-page `AnalyzeRule` instance evaluates content first and
`nextContentUrl` second. The next rule starts again from the response root by
calling `getStringList(nextRule, isUrl = true)`; it does not consume the content
rule's scalar output. Native `@put` writes made by the content rule remain visible
to the next rule because both calls share the chapter variable backing store.

`getStringList` preserves a selector list. A scalar string is split on `\n`.
Every candidate is resolved against the page `redirectUrl`, empty results are
discarded, and duplicates within that result are removed in first-seen order.

Android has two distinct pagination branches:

- Exactly one next URL: fetch serially, parse that page's content and its next rule,
  and continue while the next string is non-empty and has not appeared in the
  visited list. Before requesting, Android also stops when the candidate resolves
  to the known next chapter URL.
- More than one next URL: fetch every listed URL concurrently, append results in
  rule-list order, and parse content only. Nested `nextContentUrl` results from
  those pages are ignored.

The initial redirect URL is the first visited entry. In the serial branch, each
requested next URL is added before the fetch. Consequently a self-link or cycle
terminates without another request once it has already been visited. URL option
objects remain attached to each next URL and are parsed anew by `AnalyzeUrl`.

The first page is appended without a prefix. Every additional page is appended as
`"\n" + formattedPageContent`, including an empty page. The concurrent branch
awaits in source-rule order, so request completion order cannot reorder content.
Final purification runs once over the full joined string.

Android also parses those concurrent pages inside the child coroutines while they
share the mutable chapter variable map. That creates timing-dependent variable
visibility. Swift fetches the bodies concurrently but parses them in rule-list
order with one chapter context. Content order remains Android-compatible while
variable writes become deterministic; this is an intentional concurrency-safety
difference.

Android has no explicit maximum content-page count. Swift adds
`maximumPageCount` as a safety extension to bound hostile or accidental infinite
pagination that evades duplicate detection.

## URL bases and redirects

The requested page URL is `AnalyzeRule.baseUrl` and the JavaScript `baseUrl`
binding. The final response URL is `AnalyzeRule.redirectUrl`; it is the base for
`nextContentUrl` relative URL completion and retained image URL completion.

The next request is constructed from the already resolved next URL, including any
Legado URL options. The following page again receives its requested URL as
`baseUrl` and its own final response URL as `redirectUrl`. This differs from TOC
pagination and is implemented independently.

## Variables and `result`

Android `AnalyzeRule.put` writes to the chapter when a chapter is attached, then
falls back to the book/rule-data object. Content analysis always attaches the
chapter before rule execution, so native content `@put` values are chapter-scoped.
All pages of one content fetch reuse that chapter object and therefore share those
variables. A content rule and the following next-URL rule also share them.

Chapter lookup precedes book lookup. Different chapters have separate chapter
maps, while book variables may be shared by other Android operations through the
mutable persisted `Book`. `@put` obtains its value through `getString`; an empty
selector result becomes `""` and overwrites an earlier value. A literal null passed
directly through the Java bridge removes a value, but native `@put` does not
produce null.

Each `getString`/`getStringList` call resets its local `result` to the response
root. Within a composed scalar rule, JavaScript receives the immediately preceding
stage result. `nextContentUrl` therefore does not receive extracted content as
`result`, although it can read values stored by content through `@get`.

Swift owns a fresh chapter-variable dictionary per `fetchContent` call, shares it
across that call's pages, and never places it in global runtime state. Concurrent
chapter A and chapter B fetches cannot pollute one another. Current value-type
`BookInfoResult` and `BookChapterResult` do not persist Android book/chapter
variable maps between separate Runtime API calls; this is a documented
compatibility boundary rather than hidden shared state.

## JavaScript and platform boundaries

Ordinary synchronous rule JavaScript reuses `RuleJavaScriptExecutor`.
`java.ajax`, `java.get`, `java.post`, and `java.head` remain blocked by the
synchronous rule-execution versus asynchronous networking boundary. No production
JavaScript network bridge is introduced.

`webJs`, WebView-backed requests, `sourceRegex` WebView extraction,
`loginCheckJs`, cookies requiring a WebView, and pay actions are outside this
Core stage. URL options are still preserved by `RequestBuilder`; a production
adapter must reject or route unsupported WebView behavior explicitly rather than
pretend it executed.

## Swift API and result

The Core API is:

```swift
fetchContent(
    source: BookSource,
    book: BookInfoResult,
    chapter: BookChapterResult
) async throws -> ChapterContentResult
```

`ChapterContentResult` contains:

- `content`: the formatted, page-joined, and finally purified chapter body;
- `chapterURL`: the canonical chapter URL supplied by `BookChapterResult`.

Android ultimately returns only the content string. `chapterURL` is retained as the
minimal identity needed to associate an async result with its input chapter.
`nextURL`, source URL, chapter name, caching metadata, and reader presentation
fields are not exposed because Android content analysis does not return them.

## Known Core compatibility boundaries

- The API has no database and no next-chapter argument, so it cannot reproduce
  Android's DAO lookup and next-chapter boundary stop. Duplicate/self-loop
  termination is preserved.
- Existing value result types do not carry persisted Android book/chapter variable
  maps across Search, BookInfo, TOC, and Content calls. Content pages within one
  call do share chapter variables.
- Synthetic volume sentinel identity is not retained by the current
  `BookChapterResult`, whose URL is already canonicalized by TOC. No new raw-URL
  field is added without a broader model decision.
- The formatter retains image URLs but does not download images.
- The safety page limit is a Swift extension; Android has no corresponding hard
  limit in `BookContent`.
- Multi-URL bodies are fetched concurrently but parsed in list order, avoiding
  Android's timing-dependent concurrent mutation of chapter variables.
- Full Rhino behavior, production `java.*` networking, WebView, `webJs`,
  `sourceRegex`, `loginCheckJs`, pay actions, and source-script access to mutable
  native book/chapter objects remain unsupported.
