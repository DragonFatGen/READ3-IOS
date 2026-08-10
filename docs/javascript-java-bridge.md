# Legado JavaScript `java.*` network bridge analysis

This analysis is pinned to Android Legado commit
`c043ea72fd2698d27a7dcbc0beb7844c572e544c`. `Reference/READ3.0` was read with
`git show` and `git grep` and was not modified.

## Engine, object, and call chain

The pinned app loads `app/lib/rhino-1.7.13-1.jar`; Gradle also pins Kotlin
coroutines `1.6.1-native-mt`, OkHttp `4.9.3`, and jsoup `1.14.3`.

For rule execution, `AnalyzeRule.evalJS` binds `java` to the current
`AnalyzeRule` instance. `AnalyzeRule` implements `JsExtensions`, so Rhino can
see both its own public methods and the public methods inherited from that
interface. Other entry points bind a different receiver: `AnalyzeUrl.evalJS`
binds its `AnalyzeUrl` instance, and `BaseSource.evalJS` binds the source
instance. The Android bridge is therefore a broad Java-object bridge, not a
small network-only object. READ3-IOS must not reproduce that reflection surface;
its future `java` object is an explicit allowlist.

The rule-side `ajax` chain is:

```text
Rhino script
  -> AnalyzeRule.ajax(String)
  -> kotlinx.coroutines.runBlocking
  -> AnalyzeUrl(urlStr, source = source, ruleData = book)
  -> AnalyzeUrl.getStrResponseAwait()
  -> getProxyClient(proxy).newCallStrResponse(retry)
  -> OkHttp Call.await()
  -> StrResponse.body
```

`Call.await()` uses `suspendCancellableCoroutine`; cancellation calls OkHttp
`Call.cancel()`. The outer Rhino-visible method nevertheless blocks the current
Rhino thread until completion because it wraps the suspend path in
`runBlocking`. There is no Promise or callback visible to JavaScript.

## Exact allowlisted signatures

The fixed source has these methods:

```kotlin
fun ajax(urlStr: String): String?
fun get(urlStr: String, headers: Map<String, String>): Connection.Response
fun head(urlStr: String, headers: Map<String, String>): Connection.Response
fun post(
    urlStr: String,
    body: String,
    headers: Map<String, String>
): Connection.Response
```

There are no network overloads taking a request object, JSON option object, or
one-argument `get`. `AnalyzeRule` separately has `get(key: String)` for rule
variables, so Rhino resolves `java.get("key")` and
`java.get(url, headers)` by arity/type. That variable overload is not part of
this network phase.

The parameters are Java/Kotlin `String` values and, for headers, a Java
`Map<String, String>` produced from a JavaScript object by Rhino. `ajax` accepts
one Legado URL string. Its string may include `,{...}` URL options understood by
`AnalyzeUrl`; it is not a JavaScript object overload.

## `ajax` request behavior

`AnalyzeUrl` performs the same URL-option processing used by ordinary source
requests:

- It starts with `source.getHeaderMap(true)` and removes the pseudo-header
  `proxy`, retaining that value as transport configuration.
- URL-option `headers` overwrite source headers by key.
- `method` recognizes `POST` case-insensitively; otherwise the request is GET.
- `body`, `charset`, `retry`, `type`, `webView`, `webJs`, `js`, and extra option
  fields are parsed by `AnalyzeUrl`. WebView-related options are outside this
  phase.
- GET query fields and form POST fields are encoded by `AnalyzeUrl`; raw JSON,
  XML, and explicitly typed request bodies take different paths.
- `retry = n` results in up to `n + 1` OkHttp attempts, stopping on the first
  successful status. Connection-level OkHttp retry is also enabled.
- The standard OkHttp client follows HTTP and HTTPS redirects. Its connect,
  read, and write timeouts are 15 seconds and its total call timeout is 60
  seconds.
- A configured source concurrency rate may reject the call with
  `ConcurrentException` before transport starts.

`AnalyzeRule.ajax` constructs `AnalyzeUrl` without its `baseUrl` argument.
Because that constructor defaults `baseUrl` to `""`,
`NetworkUtils.getAbsoluteURL` leaves a relative string unchanged. The
`baseUrl` JavaScript binding is readable by the script, but it is not implicitly
used by `java.ajax`. A source wanting relative behavior must construct the
absolute URL itself, for example `java.ajax(baseUrl + "/path")`.

The source object is passed to `AnalyzeUrl`, so source headers, source identity,
proxy configuration, concurrency rate, and the book-backed `RuleDataInterface`
are available to the request pipeline. `book`, `chapter`, and the other rule
bindings are not request parameters by themselves.

## Cookie behavior

Immediately before an `ajax` request, `AnalyzeUrl.setCookie(source.getKey())`
loads the global Android `CookieStore`. Stored cookies are merged with a
request `Cookie` header; request/header cookies win on duplicate names. The
merged value is written into the outgoing header map.

OkHttp's cookie jar deliberately returns an empty list from `loadForRequest`,
because request injection is handled above. Its `saveFromResponse` persists
every response cookie through `CookieStore.replaceCookie`, keyed by the response
URL's registrable domain. Consequently `Set-Cookie` updates are visible to
subsequent `ajax` calls.

`get`, `post`, and `head` use a new `Jsoup.connect` object for every call. They
do not add source headers, read the Android `CookieStore`, or write responses
back to it. A caller may explicitly provide a `Cookie` header. Cookies remain
available on the returned `Connection.Response`, but no jsoup session is
retained across calls.

## Response, status, decoding, and failures

`java.ajax` returns only `StrResponse.body`, a nullable string. OkHttp response
status is not exposed. `newCallResponse` retries non-success statuses and
returns the final response even when it is 4xx or 5xx; `newCallStrResponse`
therefore returns that response body, or the HTTP status message when the body
is absent.

Transport, URL, option-processing, decoding, proxy, concurrency-rate, and other
throwables inside `AnalyzeRule.ajax` are caught by `runCatching`. Android logs
the failure and returns `Throwable.msg`. In this commit `msg` normally contains
`stackTraceToString()`, not `null`, an empty string, or a JavaScript exception.
This can expose Android implementation details and is not deterministic across
platforms; an iOS implementation should preserve the observable “error becomes
a string” category while using a stable redacted message.

OkHttp body decoding removes a UTF-8 BOM, then uses the response Content-Type
charset, and otherwise runs Legado's content encoding detector. The URL option
`charset` controls request query/form encoding; it is not passed as an explicit
response decoder override on this path. Android can decode encodings such as
GBK through JVM charsets and its detector. READ3-IOS currently rejects
GBK/GB2312/GB18030/Big5 and must not silently substitute UTF-8.

`java.get`, `java.post`, and `java.head` have different behavior. They call
jsoup synchronously, set `ignoreContentType(true)` and
`followRedirects(false)`, and leave `ignoreHttpErrors` at its default `false`.
Malformed URLs, transport failures, timeouts, and 4xx/5xx responses therefore
throw into Rhino. They do not use AnalyzeUrl options, source proxy, retries, or
base-URL completion. The POST body is passed verbatim to jsoup `requestBody`.
The HEAD method exists in source even though the pinned help text only documents
GET and POST.

jsoup decodes `Response.body()` using the response charset it derives from the
content type and document bytes. Its independent defaults, including its body
size and timeout, apply to these three calls; they are not the OkHttp settings
used by `ajax`.

## Rhino-visible `Connection.Response`

The return object is the real jsoup 1.14.3 `Connection.Response`. Rhino can
reflect its public response and inherited `Connection.Base` methods, including:

- `body()`, `bodyAsBytes()`, `parse()`, and `bufferUp()`;
- `statusCode()` and `statusMessage()`;
- `charset()` and `charset(String)`;
- `contentType()`;
- `header(String)`, `headers()`, `multiHeaders()`, `hasHeader(...)`, and the
  response header mutators;
- `cookie(String)`, `cookies()`, `hasCookie(...)`, and cookie mutators;
- `url()` / `url(URL)`;
- `method()` / `method(Connection.Method)`.

This is a mutable Java object with more surface than source scripts normally
need. The pinned help fixture demonstrates
`java.post(url, body, {}).header("Location")`; other common consumption uses
`body()` and `statusCode()`. READ3-IOS should return an immutable explicit
snapshot with only reader methods and should not expose Java-style mutators,
`parse()` DOM objects, streams, request objects, or reflection.

## Nesting, shared state, and deferred bindings

A script can make several sequential calls, and a callback can execute another
JavaScript rule through other broad Android methods, so nested behavior is not
forbidden by Rhino. Each network call blocks the same current evaluation thread.
Android supplies no per-script call count, response-size budget for the OkHttp
`ajax` path, recursion budget, or JavaScript execution deadline.

The fixed rule binding also includes `cookie`, `cache`, `source`, `book`,
`chapter`, `title`, `src`, and `nextChapterUrl`; `AnalyzeUrl` adds `page`, `key`,
speech fields, and a more specific `book`. These are analysis results only in
this phase. The future iOS allowlist is limited to `ajax/get/post/head` and will
not expose Android Java reflection, file APIs, CacheManager, CookieStore,
WebView, browser/login helpers, or arbitrary source/book/chapter objects.

## Foundation-stage compatibility matrix

| Android behavior | Current Swift foundation | Compatibility | Later work |
| --- | --- | --- | --- |
| Synchronous `ajax(String)` body result | Host protocol and mock contract only | Structural | Dedicated worker plus safe transport |
| `ajax` URL options / source headers | Existing async `RequestBuilder` identified for reuse | Not wired | Async runtime orchestration |
| `ajax` 4xx/5xx body | Recorded in contract | Not executed | Transport adapter tests |
| `ajax` transport failure becomes text | Stable host error policy specified | Near, mock only | Production error redaction |
| Cookie load/merge/persist | Existing async `HTTPCookieStore` identified | Not wired | Async runtime orchestration |
| `get/post/head` return Response | Immutable response snapshot contract | Structural | Production transport |
| Redirect disabled for `get/post/head` | Recorded | Not executed | Production transport |
| JavaScriptCore `java` object | Optional allowlisted mock host | Safe mock compatibility | Production host after worker |
| Infinite-loop termination | No public Apple termination API found | Unsupported | Runtime/process isolation decision |
