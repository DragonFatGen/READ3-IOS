# Legado JavaScript rule execution foundation

This compatibility analysis is pinned to Android Legado commit
`c043ea72fd2698d27a7dcbc0beb7844c572e544c`. All Android source and the bundled
JAR were read in place with `git show`, `git grep`, `javap`, and archive metadata;
`Reference/READ3.0` was not modified.

## Engine and dependency evidence

The application uses the process-wide lazy `AppConst.SCRIPT_ENGINE`, whose
concrete type is `com.script.javascript.RhinoScriptEngine`. `app/build.gradle`
loads `app/lib/rhino-*.jar`; the pinned tree contains
`app/lib/rhino-1.7.13-1.jar`. Its manifest identifies Mozilla Rhino,
implementation version `1.7.13-1`, bundle version `1.7.13`, built on 2022-04-22.
The commented Maven alternative is `com.github.gedoor:rhino-android:1.8`, but it
is not the dependency selected by this commit.

Bytecode inspection confirms that the engine creates one shared Rhino top-level
scope, enters/exits a Rhino `Context` for every evaluation, and creates an
`ExternalScriptable` runtime scope over the supplied `SimpleBindings`. Returned
Java wrappers are unwrapped. Rhino `Undefined` is converted to Java `null` by
`RhinoScriptEngine.unwrapReturnValue`; an actual JavaScript `null` is also Java
`null`, so the application cannot distinguish the two after `eval` returns.

Rhino syntax/runtime exceptions are wrapped as `com.script.ScriptException` by
the engine. Neither `AnalyzeRule.evalJS` nor its string/list/element pipeline
catches that exception. There is therefore no Android “compatible mode returns
empty” behavior for JavaScript errors.

## Rule entry points and call chain

The production rule path is:

```text
BookList / BookInfo / BookChapterList / BookContent / RSS
-> AnalyzeRule.getString, getStringList, getElement, or getElements
-> AnalyzeRule.splitSourceRule
-> SourceRule.makeUpRule
-> AnalyzeRule.evalJS
-> AppConst.SCRIPT_ENGINE.eval(script, SimpleBindings)
```

`AppPattern.JS_PATTERN` is case-insensitive and matches
`<js>([\w\W]*?)</js>|@js:([\w\W]*)`.

- `@js:` consumes the complete remaining rule as one JavaScript stage. It is not
  split again on `&&`, `||`, `%%`, `##`, or selector syntax.
- A balanced `<js>...</js>` contributes one JavaScript stage between the source
  rules before and after it. Multiple blocks form an ordered pipeline.
- An unterminated `<js>` is not a JavaScript match and remains ordinary rule
  text.
- Each stage receives the preceding stage's object as `result`. A null stage
  result prevents subsequent stages because Android continues inside
  `result?.let`.
- A JavaScript-produced string is not reparsed as a new source rule. The next
  already-parsed stage consumes it as input.

`AnalyzeUrl` uses the same pattern for URL rules, but requires each standalone JS
segment to return a `String` (`as String`). URL-option `js` instead uses
`toString()`. Those URL behaviors are outside this pure rule-execution phase.

## Template JavaScript

`SourceRule.makeUpRule` processes every balanced `{{...}}` before selector
dispatch and before the final `##` replacement fields are separated. A body
starting with `@`, `$.`, `$[`, or `//` is evaluated recursively as a rule. Every
other body, including an empty body, is evaluated as JavaScript with the current
pipeline object as `result`.

Template interpolation uses these conversions:

- null or undefined: inserts nothing;
- `String`: inserts the string unchanged;
- integral `Double`: inserts fixed decimal text with no `.0`;
- any other result: inserts Java/Kotlin `toString()`.

The expanded outer text is not parsed again. Operators produced by JavaScript
remain literal text. `AnalyzeUrl` and `JsUtils.evalJs` apply the same integral
`Double` special case to their `{{...}}` forms.

## Bindings visible to rule JavaScript

`AnalyzeRule.evalJS` installs a fresh `SimpleBindings` for every call:

| Binding | Android source |
| --- | --- |
| `java` | the current `AnalyzeRule` (`JsExtensions` and rule helper methods) |
| `cookie` | global `CookieStore` |
| `cache` | global `CacheManager` |
| `source` | constructor `BaseSource?`; `bookSource` is not a separate binding |
| `book` | `ruleData as? BaseBook` |
| `result` | the object passed from the preceding rule stage |
| `baseUrl` | `AnalyzeRule.baseUrl`, set by `setContent`/`setBaseUrl` |
| `chapter` | current `BookChapter?` |
| `title` | `chapter?.title` |
| `src` | the original analyzer `content`, not necessarily current `result` |
| `nextChapterUrl` | the analyzer's next-chapter URL |

`AnalyzeUrl.evalJS` has a related but different set: `java`, `baseUrl`,
`cookie`, `cache`, `page`, `key`, `speakText`, `speakSpeed`, `book`, `source`, and
`result`. This phase models the rule-executor boundary, not URL analysis.

READ3-IOS currently has platform-neutral `RuleValue`, `baseUrl`, source
variables, and temporary variables. Its JavaScript snapshot therefore carries
the current result, base URL, and both variable maps. It does not invent book,
chapter, source model, cookie, cache, or networking objects before Core has safe
platform-neutral representations for them. Source identifier and source URL are
not part of the existing `RuleExecutionContext`, and are not added speculatively.

## `RuleDataInterface`, `@put`/`@get`, and JavaScript

Android `@put:{...}` evaluates assignments before the main stage and writes by
calling `AnalyzeRule.put`. `@get:{key}` calls `AnalyzeRule.get`. The lookup order
is chapter, book, then transient/source `RuleData`; two special names expose
book name and chapter title. JavaScript reaches the same methods through
`java.put(...)` and `java.get(...)`; arbitrary RuleData entries are not injected
as JavaScript global variables.

The current Swift context already models source and temporary variable maps for
native `@put/@get`. They are included as immutable snapshots for isolation and a
future allowlisted `java` bridge, but the JavaScriptCore adapter in this phase
does not register `java` or expose map entries as globals. It does not create a
second variable store.

## Return values entering `AnalyzeRule`

Android retains the raw `Any?` returned by Rhino until the surrounding API
converts it:

| Rhino result | Engine/application behavior | Swift foundation mapping |
| --- | --- | --- |
| `undefined` | engine unwraps it to Java null | `.undefined` then `RuleValue.none` |
| `null` | Java null | `.null` then `RuleValue.none` |
| string | Java `String` | `RuleValue.string`, unchanged |
| number | normally Java `Double`; direct string path uses `Double.toString()` | deterministic JavaScript-number spelling; template integral values omit `.0` |
| boolean | Java `Boolean.toString()` (`true`/`false`) | lowercase string |
| array | Rhino `NativeArray`, which implements Java `List` | recursively mapped to `RuleValue.strings` |
| object literal | Rhino `NativeObject`, which implements Java `Map`; direct `toString()` is `[object Object]` | compact JSON with lexicographically sorted keys |
| Java `List`/`Map` | may be returned through the unrestricted `java` bridge | not constructible in this phase; adapter maps JavaScript arrays/objects only |

`getString` finally applies `result.toString()` (then HTML entity unescaping).
`getStringList` splits a returned `String` on newlines; a `NativeArray` is a
`List`, while other non-list values do not become a string list. Element APIs
retain raw objects longer and cast the final result to the required shape.

Swift's existing executor has one platform-neutral `RuleValue` result boundary,
so it cannot preserve a Rhino DOM node or Java object. A dedicated
`JavaScriptExecutionResult` retains null/undefined, scalar, array, and object
shapes until Core performs a documented conversion. Arrays are recursively
stringified into list members. Objects use sorted-key compact JSON instead of
Android's unhelpful `[object Object]`; this is an intentional deterministic
difference and avoids platform/hash-dependent descriptions. Nested arrays and
objects use the same compact JSON representation when one string member is
required.

## Exceptions and policies

Syntax errors, `ReferenceError`, `TypeError`, explicitly thrown JavaScript
values, and other Rhino failures escape `AnalyzeRule`. READ3-IOS therefore
throws a typed JavaScript execution failure under both `.legadoCompatible` and
`.strict`. Compatible mode does not silently return `.none`. The error records a
technical message, but does not include cookies, headers, credentials, variable
snapshots, or the complete script.

## `java` network bridge analysis (deferred)

The pinned `JsExtensions` interface exposes several synchronous calls to Rhino:

- `java.ajax(urlStr: String): String?` builds `AnalyzeUrl`, blocks with
  `runBlocking`, and returns response body. Failures are logged and converted to
  `Throwable.msg` text rather than rethrown.
- `java.ajaxAll(urlList: Array<String>): Array<StrResponse?>` starts IO
  coroutines in `runBlocking`, awaits in input order, and returns response
  wrappers. Individual failures are not caught in this default implementation.
- `java.connect(urlStr[, headerJson]): StrResponse` performs an `AnalyzeUrl`
  request and returns URL/body; errors become a response whose body is the
  localized error.
- `java.get(urlStr, headers): org.jsoup.Connection.Response` uses jsoup, unsafe
  TLS, ignores content type, does not follow redirects, sends GET, and returns
  the response object (status, headers, cookies, charset/body through jsoup).
- `java.post(urlStr, body, headers): org.jsoup.Connection.Response` uses the
  same jsoup settings, sends the supplied raw request body, and does not follow
  redirects.
- `java.head(urlStr, headers)` is the analogous HEAD operation.

`AnalyzeRule.ajax` is another synchronous `runBlocking` implementation that
passes source and book context to `AnalyzeUrl`. `AnalyzeUrl` applies source and
login headers, cookies, request options, charset/form encoding, retry, proxy,
and WebView options before HTTP execution as documented in
`docs/http-request-engine.md`.

Core `HTTPClient.send` is asynchronous while `RuleExecutor.execute` is
synchronous. The follow-up architecture analysis and exact method behavior are
in `docs/javascript-java-bridge.md` and
`docs/javascript-network-bridge-architecture.md`. That phase adds value
contracts, limits, and an optional immediate mock host, but deliberately does
not bridge production network I/O with a semaphore, condition variable,
run-loop spin, detached task, or blocking wait.

## WebView behavior (deferred)

URL option `webView` selects `BackstageWebView`. For POST, Android first performs
the HTTP POST and loads the returned HTML at the response URL; for GET it loads
the URL. Source headers and source-key cookies are supplied. `webJs` (or a
caller-provided fallback script) runs after page completion and can determine
the returned body. The separate login and browser activities use Android
WebView and synchronize source login/cookie state through their own flows.

This is a browser execution path, not Rhino rule execution. No WebKit,
`WKWebView`, browser DOM, WebView cookie synchronization, `webJs`, or login UI is
implemented in this phase.

## Compatibility matrix

| Android behavior | Swift foundation stage | Compatibility | Later stage |
| --- | --- | --- | --- |
| Rhino 1.7.13-1 pure expressions | injectable synchronous executor; JavaScriptCore adapter | common ECMAScript subset, not engine parity | Rhino/JavaScriptCore fixtures |
| ordered `@js:` / `<js>` stages | existing sequence IR calls adapter | yes | broader object shapes |
| rule-shaped vs JS template bodies | existing parser boundary retained | yes | broader value fixtures |
| `result` binding | `RuleValue` snapshot injected | yes for none/string/string-list | DOM/raw Java values |
| `baseUrl` binding | Core base URL injected | yes, except Swift currently uses empty rather than nullable default | nullable URL context if required |
| source/temporary RuleData | immutable context snapshots, not JS globals | structural only | allowlisted `java.get/put` |
| `source`, `book`, `chapter`, `src` | not injected | no | typed domain snapshots/bridges |
| null vs undefined | preserved by adapter result, both become `.none` | more observable internally; same pipeline stop | consumer-specific APIs |
| string/boolean/number | explicit conversion | yes for covered fixtures | numeric edge fixtures |
| arrays | explicit recursive list conversion | close for string-list use | raw element/list values |
| objects/maps | sorted compact JSON | intentional deterministic difference | richer platform-neutral values if justified |
| JS exception propagation | typed error in both policies | yes | structured source locations |
| shared Rhino top-level | fresh JavaScriptCore context per execution | intentional isolation improvement | optional source-scoped state |
| `java.ajax/get/post/head` | allowlisted contract and immediate mock-host adapter; no production transport | structural only | dedicated worker and safe transport |
| cookies and cache | absent | no | async runtime/cookie orchestration |
| WebView DOM and `webJs` | absent | no | dedicated WebView stage |

Known numeric edge differences remain for negative zero, very large exponent
formatting, `NaN`, and infinities because Java `Double.toString`/`String.format`
and Swift/JavaScriptCore do not promise identical spelling. Covered finite
integers and ordinary decimals follow the Android direct-vs-template distinction.

## Adapter lifecycle and concurrency

Android shares one `RhinoScriptEngine` and top-level prototype but supplies a
fresh bindings/runtime scope per evaluation. For this foundation, the Apple
adapter creates a fresh `JSContext` for every call. The context and every
`JSValue` remain stack-local and never cross the protocol boundary. This avoids
cross-source/test pollution, makes independent executor instances safe to call
concurrently, and requires neither a global singleton nor `@unchecked
Sendable`. Pure JavaScriptCore has no UI requirement, so the adapter is not
`MainActor` isolated.

The adapter rejects scripts larger than 1,000,000 UTF-8 bytes, result containers
larger than 100,000 members, and result nesting deeper than 64 levels. These are
deterministic input/result bounds, not an instruction timer. JavaScriptCore's
public high-level API does not provide a safe way to interrupt an infinite loop,
so hostile-script time limits remain an explicit blocker for production-grade
untrusted execution rather than being faked with thread blocking.

## Deferred capabilities

- production network transport for `java.ajax`
- production network transport for `java.get`
- production network transport for `java.post`
- production network transport for `java.head`
- Cookie JS bridge
- WebView
- `webJs`
- login JS
- source-specific persistent JS state
- browser DOM
- Android Java object reflection
- full Rhino and JavaScriptCore semantic equivalence
- cancellable instruction/time limits for hostile infinite loops (the public
  high-level `JSContext` API has no interruption hook; a private JavaScriptCore
  API is not acceptable for App Store code)

This foundation must not be described as complete Legado JavaScript
compatibility.
