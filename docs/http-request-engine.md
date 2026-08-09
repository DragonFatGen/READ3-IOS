# Legado HTTP request engine

This analysis is pinned to Android Legado commit
`c043ea72fd2698d27a7dcbc0beb7844c572e544c`. The Android checkout was read from
the system temporary directory; `Reference/READ3.0` was not changed.

## Android implementation evidence

The primary path is `WebBook` -> `AnalyzeUrl` -> the request-builder extensions
in `OkHttpUtils` -> the shared or proxy-specific `OkHttpClient` in `HttpHelper`.
`StrResponse` retains the OkHttp response and decoded text and reports the
network request URL when one exists. `BookSource.searchUrl` is evaluated with
`key`, `page`, `bookSourceUrl` as the initial base URL, source/login headers, and
isolated rule data. Explore URLs receive `page` and the same source context.
`loginUrl` may itself be a URL or JavaScript-driven login definition; executing
that login flow is outside this phase.

`AnalyzeUrl` first handles JavaScript segments and `{{...}}`, then replaces the
historical page alternatives written as `<first,second,last>`, and finally
splits URL options. READ3-IOS only evaluates variable-shaped templates through
the existing `RuleParser` and `RuleExecutor`. Arbitrary JavaScript remains
explicitly unsupported.

## URL option syntax

The boundary is the first comma, with optional surrounding whitespace, whose
next non-whitespace character is `{` (`\s*,\s*(?=\{)` in Android). The portion
before it is resolved relative to `baseUrl`; the remainder is decoded as one
JSON object.

Android's `AnalyzeUrl.UrlOption` fields at the pinned commit are:

| Field | Android behavior | This phase |
| --- | --- | --- |
| `method` | Only case-insensitive `POST` changes the default GET | GET/POST modeled; unknown values fall back in compatible mode and throw in strict mode |
| `headers` | Object or JSON-object string; values use `toString()` | Parsed and merged case-insensitively |
| `body` | String, JSON object, or JSON array serialized back to text | Preserved and converted to form or raw bytes |
| `charset` | URL/form parameter encoding; `escape` has special JavaScript-style escaping | Preserved; UTF-8 form encoding implemented, other encoders are explicit future work |
| `retry` | Additional attempts after the first, stopping on a successful status | Preserved and implemented by the URLSession adapter |
| `type` | Switches to byte/hex handling | Preserved only |
| `webView` | Any value except null, empty, false, or `"false"` enables WebView | Preserved as `requiresWebView` only |
| `webJs` | Script run by the background WebView | Preserved as JavaScript-required metadata |
| `js` | Replaces the final URL with a JavaScript result | Preserved as JavaScript-required metadata; not executed |

`proxy` is not a declared `UrlOption` property at this commit. Android obtains
it from the source/header map using the lowercase key `proxy`, removes it from
HTTP headers, and selects a cached HTTP or SOCKS client. READ3-IOS preserves a
URL-option proxy extension and the Android header form but does not execute it.
There is no URL option for redirect or timeout in this revision.

Legacy source migration converts `@Header:{...}`, `|charset=...`, old
`url@body` POST syntax, `searchKey`, and `searchPage` into the modern URL plus
JSON-option representation before request analysis.

Malformed option JSON is ignored by Android's nullable Gson result. The Swift
builder mirrors that in compatible mode and exposes `invalidRequestOptions` in
strict mode.

## Request construction

`HTTPRequest` is the public, platform-neutral request description. It contains
Foundation `URL` and `Data`, but never exposes `URLRequest`. It records method,
case-insensitive headers, raw body bytes, body kind, parameter charset,
redirect policy, cookies, timeout, retry count, and the preserved options.

`RequestBuilder.build` is asynchronous only because an injected cookie store is
an isolated dependency. It accepts either a source-header string or a
`BookSource`. `RequestBuildContext` explicitly provides keyword/key, page,
pageSize, sourceUrl, baseUrl, source variables, source identity, timeout,
redirect policy, and error policy. It has no global state. Exact variable forms
such as `{{key}}`, `{{keyword}}`, `{{page}}`, `{{pageSize}}`, `{{sourceUrl}}`,
and source-variable names are routed through the existing rule template and
variable execution path. Arbitrary `{{JavaScript}}` is not emulated.

## Header priority and POST behavior

Android initializes source headers with the application User-Agent, overlays
the source JSON header, overlays saved login headers, then overlays URL-option
headers. The OkHttp interceptor only supplies its User-Agent when no request
header exists. READ3-IOS implements the available equivalent priority:

1. builder default User-Agent;
2. source header;
3. request-specific URL-option header.

Header names are compared case-insensitively. Login-header persistence is not
yet represented by `BookSource`, so callers may include it in the supplied
source header at this boundary.

For POST, Android parses a body into form fields only when it is neither JSON
nor XML and no Content-Type header exists. Empty body also becomes an empty
form. A raw body with an explicit Content-Type uses that exact media type. A raw
body without one is sent by `postJson` with
`application/json; charset=UTF-8`; Android does not assume every supplied body
was originally a JSON object. Form requests use
`application/x-www-form-urlencoded`.

GET query and form field values are encoded before OkHttp receives them.
Android supports Java charset names and the special `escape` value. The current
cross-platform builder implements deterministic UTF-8 form encoding and throws
`unsupportedCharset` rather than treating GBK-family input as UTF-8.

## Response and text decoding

`HTTPResponse` always retains status, headers, raw `Data`, final URL, redirect
metadata, and response cookies. Text decoding is a separate operation through
`TextDecoder`. The selection order is explicit caller charset, Content-Type
charset, then UTF-8.

Android removes a UTF-8 BOM, then uses an explicitly passed decoder charset,
then the Content-Type charset, then HTML/content encoding detection. Its normal
`AnalyzeUrl.getStrResponseAwait` path does not pass the URL option `charset` to
the response decoder. READ3-IOS likewise keeps request parameter charset
separate from response decoding.

`FoundationTextDecoder` currently supports UTF-8, UTF-16 variants, ASCII, and
ISO-8859-1. GBK, GB2312, GB18030, and Big5 are recognized but deliberately
reported as unsupported. A later platform-neutral decoder implementation can
add them behind the protocol without changing HTTP clients or response models.
HTML encoding detection is also deferred.

## Redirects, status, and errors

Android OkHttp follows HTTP and HTTPS redirects and uses 15-second connect,
write, and read timeouts plus a 60-second call timeout. It retries the complete
request `retry + 1` times until `Response.isSuccessful`, then returns the final
unsuccessful response rather than throwing an HTTP-status exception.

The URLSession adapter uses a 60-second request timeout by default, records
followed redirects, supports a no-follow policy and a maximum hop count, retries
on non-2xx status, and retains the last response. Transport and malformed
response failures are typed separately. Exact OkHttp timeout partitioning,
unsafe TLS behavior, Cronet, and authenticated proxies are not reproduced.

## Cookies

Android's `CookieStore` groups cookies by effective registrable domain and its
OkHttp jar saves each response cookie back into that store. Before a request,
the source-key cookie is merged with a URL-option `Cookie` header, with the
request-specific cookie values winning.

Core defines `HTTPCookie`, `HTTPCookieStore`, and an actor-based
`InMemoryHTTPCookieStore`. Stores can scope values by source identifier for test
and source isolation; no shared `HTTPCookieStorage` is used. `RequestBuilder`
merges stored cookies with a request Cookie header using the same override
direction. The URLSession adapter parses basic Set-Cookie metadata into the
response, while persistence remains an explicit caller/store action. Public
suffix calculation, SameSite, Max-Age/Expires parsing, and a persistent jar are
deferred.

## Platform adapter and mock

`HTTPClient` exposes only `send(_:) async throws -> HTTPResponse`.
`URLSessionHTTPClient` conditionally imports `FoundationNetworking`, disables
URLSession's shared cookie state, translates the domain request internally, and
does not parse HTML, JSON, or source rules.

`MockHTTPClient` is an actor with configured response/error results and captured
requests. Tests remain deterministic and never access the public internet.

## Deferred capabilities

- JavaScript, `java.ajax`, `java.get`, `java.post`, and URL-option `js`;
- WebView loading, `webJs`, login pages, and cookie synchronization with WebView;
- proxy execution, Cronet, unsafe TLS compatibility, multipart upload, `type`
  byte/hex transformation, concurrent-rate throttling, and persistent cookies;
- GBK/GB2312/GB18030/Big5 decoding and HTML charset detection;
- search, explore, book-info, TOC, content orchestration, and all UI.
