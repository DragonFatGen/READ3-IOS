# Cookie and source session foundation

This analysis is pinned to Android Legado commit
`c043ea72fd2698d27a7dcbc0beb7844c572e544c` under `Reference/READ3.0`.

## Fixed Android call chain

`AnalyzeUrl` starts with `source.getHeaderMap(true)`, then applies URL-option
headers by key. An option `Cookie` therefore replaces the complete source-header
`Cookie` string. Immediately before Search, Explore, BookInfo, TOC, Content, image,
or byte requests, `AnalyzeUrl.setCookie(source.getKey())` reads `CookieStore`,
converts both strings to name/value maps, and applies the request header map over
the stored map. The resulting header is sent explicitly through OkHttp.

The process-wide OkHttp client installs `HttpHelper.cookieJar`. Its
`loadForRequest` always returns an empty list: the jar never creates a request
header. `saveFromResponse` receives OkHttp-parsed cookies and calls
`CookieStore.replaceCookie(responseURL, "name=value")` for each one. This occurs
for Search, Explore, BookInfo, TOC, Content, and every OkHttp redirect exchange.

`CookieStore` reduces its key to the effective TLD plus one using OkHttp's
`PublicSuffixDatabase` (or the IP/host fallback), caches the string in memory,
and stores it in the Room `cookies` table. It is global by registrable domain,
not per `BookSource`. Two sources using the same effective domain see the same
stored string. When a source URL and request URL use different effective domains,
the source-key lookup and response-URL write can address different records.

Android discards Domain, Path, Secure, HttpOnly, Expires, Max-Age, and host-only
metadata when writing `CookieStore`. Same-name values overwrite through a map.
Consequently Android has no different-path same-name representation, no automatic
expiry/delete behavior, and persists cookies without expiry—including HTTP
session cookies—across app restarts until explicit removal or replacement.

## Redirect behavior

OkHttp follows HTTP and HTTPS redirects. Each intermediate `Set-Cookie` is passed
to `saveFromResponse` and persisted. Because `loadForRequest` is always empty and
`AnalyzeUrl.setCookie` runs only before the outer call, that newly saved value is
not injected by the CookieJar into the immediately following redirect request.
It becomes visible to later top-level requests.

READ3-IOS deliberately improves this edge: `CookieSessionHTTPClient` executes
redirect hops explicitly, stores every response before the next hop, and rebuilds
the next Cookie header from the shared store. A `302 + Set-Cookie` can therefore
authenticate its next hop. This is RFC/browser behavior but differs from the fixed
Android jar implementation.

## Request precedence

Android precedence is:

1. source headers initialize the header map;
2. URL-option headers replace same-named source headers (including the complete
   `Cookie` string);
3. the surviving explicit Cookie values override same-name stored values.

For stored `a=1; b=2`, source `b=3; c=4`, and URL option `c=5; d=6`, the option
Cookie replaces the source Cookie and the effective values are
`a=1; b=2; c=5; d=6`. Header order is not a compatibility guarantee on Android;
READ3-IOS emits a deterministic order.

## READ3-IOS model and storage

`HTTPCookie` retains name, value, normalized domain, path, expiry, Secure,
HttpOnly, and `isHostOnly`. Missing `isHostOnly` in older Codable data decodes as
`false`, preserving the former domain-cookie behavior. Matching implements exact
host-only checks, label-boundary domain matching, RFC path boundaries, Secure,
and expiry. Max-Age is resolved to an absolute expiry by `SetCookieParser` and
takes precedence over Expires. Max-Age zero creates an immediately expired
replacement, which deletes the name/domain/path identity.

`SetCookieParser` handles separate or combined header values, Expires commas,
case-insensitive attributes, whitespace, values containing `=`, leading-dot
domains, default paths, and host-only cookies. Invalid cross-domain Domain
attributes are rejected.

`InMemoryHTTPCookieStore` and the Apple persistent store share
`HTTPCookieCollection`. Cookie visibility is global by URL domain/path, matching
Android's cross-source behavior. `sourceIdentifier` records the owner so removing
one source's stored records is possible; it is not a visibility partition.
Identity is name + domain + path, as in standard cookie stores; host-only is a
matching attribute and does not create a second same-identity cookie.

Apple production persistence stores the encoded collection as a generic-password
Keychain item with `AfterFirstUnlockThisDeviceOnly` accessibility. It does not use
UserDefaults. Expired values are removed on restore, read, and write. Session
cookies are persisted to match fixed Android behavior, even though desktop
browser session semantics often discard them at process exit.

## Shared runtime session

`AppDependencies.live()` creates one `PersistentHTTPCookieStore`, one
`URLSessionHTTPClient` transport with system cookie storage disabled, and one
`CookieSessionHTTPClient`. All five production runtimes receive that same client:

`Search / Explore -> BookInfo -> TOC -> Content`

Response persistence is automatic. No runtime calls `store(response.cookies)`.
`HTTPRequest.sessionIdentifier` carries the source key without embedding a
`BookSource` or Apple type in Core.

## WebView and JavaScript boundaries

`WebCookieSynchronizing` reserves two operations for the future adapter:

- before navigation, native store -> `WKHTTPCookieStore`;
- after login/page completion, `WKHTTPCookieStore` -> native store.

The fixed Android login WebView performs the equivalent explicit push/pull with
`android.webkit.CookieManager`, saving the pulled string under `source.getKey()`.
No WKWebView, login UI, or loginCheckJs is implemented in this phase.

Android exposes `java.getCookie(tag, key?)` as a CookieStore string/map lookup;
scripts can also access the bound `cookie` manager's set/get/remove methods.
Those bridges are not connected yet. The shared async session is reusable by a
future bounded JavaScript transport, but this phase adds no blocking shim and no
production `java.ajax/get/post/head`.

## Known differences and deferred behavior

- READ3-IOS honors Domain, Path, Secure, HttpOnly metadata, expiry, and deletion;
  fixed Android flattens these to name/value strings.
- READ3-IOS sends a redirect response cookie on the next hop; fixed Android saves
  it but its empty `loadForRequest` does not inject it into that hop.
- READ3-IOS currently does not calculate effective TLD plus one for storage;
  standards-based domain matching determines visibility. Public-suffix rejection
  remains deferred.
- SameSite, cookie priority, partitioned cookies, WebView synchronization,
  loginCheckJs, WebView login, and JavaScript network hosts remain unsupported.
