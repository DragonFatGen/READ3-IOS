# JavaScript network bridge architecture

This decision is based on Android Legado commit
`c043ea72fd2698d27a7dcbc0beb7844c572e544c`, the current synchronous
`RuleExecutor`, the async `HTTPClient`, and public JavaScriptCore APIs available
in the Apple SDK. It deliberately does not treat a passing mock as proof that a
safe production network bridge exists.

## Constraints established by the source

Android JavaScript observes a synchronous API: `java.ajax(...)` returns a
string before the next JavaScript statement runs, and `java.get/post/head`
return a response object immediately. Android obtains that behavior by running
the suspend OkHttp path inside `runBlocking` on the current Rhino thread.

READ3-IOS has two intentionally different boundaries:

- `RuleExecutor.execute` and `RuleJavaScriptExecutor.execute` are synchronous;
- `HTTPClient.send`, `RequestBuilder.build`, and `HTTPCookieStore` are async.

JavaScriptCore's documented `JSContext.evaluateScript` is synchronous. Public
`JSContext` and `JSVirtualMachine` APIs document evaluation, value bridging,
thread safety, and independent virtual machines, but expose no supported
execution deadline, context-group interrupt, or forced termination method.
Undocumented WebKit/JavaScriptCore symbols are not acceptable.

Making only the outer Swift method async does not let an arbitrary running
JavaScript program suspend at a native synchronous callback and resume later.
That is the central architecture boundary.

## Option A: make all rule execution async

This would change `RuleExecutor.execute` and recursively async-enable selectors,
regex, templates, variables, and every current caller.

| Concern | Assessment |
| --- | --- |
| Android synchronous JS semantics | Insufficient by itself; JavaScriptCore callbacks still cannot `await` Swift automatically |
| Existing RuleExecutor | Large public/API and test migration |
| HTTPClient | Natural async fit outside JavaScript evaluation |
| Windows tests | Testable, but broad churn unrelated to selectors |
| JavaScriptCore | Still needs Promise semantics or a separate blocking boundary |
| Cancellation / timeout | Good for orchestration and HTTP, not for an infinite `evaluateScript` |
| Deadlock / MainActor | Avoidable if callers await off MainActor; callback problem remains |
| Thread starvation | Low for HTTP; infinite JS can still occupy a worker |
| Nested `java.ajax` | Cannot preserve immediate return without another mechanism |
| WebView / future services | Good async service shape |
| Migration cost | High, while failing to solve the core callback issue |

Decision: reject as the immediate bridge solution. A future async orchestration
layer is valuable, but converting every deterministic rule does not create a
synchronous JavaScript host callback.

## Option B: async runtime orchestration plus a dedicated JavaScript worker

Add an `AsyncRuleRuntime`/book-source orchestration layer above the current
executor. It owns request/cookie services and schedules an entire synchronous
JavaScript evaluation on a bounded dedicated native-thread worker. Within that
worker, a purpose-built synchronous transport boundary supplies the immediate
host return required by JavaScript.

The synchronous transport must be a real independently implemented contract. It
must not call async `HTTPClient.send` and wait with a semaphore, condition,
RunLoop, polling, or a blocked Swift `Task`. It must support transport-level
timeout and cancellation directly, and the worker must never be the MainActor
or a Swift cooperative executor worker.

| Concern | Assessment |
| --- | --- |
| Android synchronous JS semantics | High: immediate host results are possible |
| Existing RuleExecutor | Remains synchronous and unchanged |
| HTTPClient | Remains async for normal app traffic; request/response models can be shared |
| Windows tests | Host contracts, budgets, and worker scheduling can use fakes |
| JavaScriptCore | Evaluation and host callback remain on one dedicated thread/context |
| Cancellation / timeout | Transport can be cancelled; engine-level infinite-loop cancellation remains unsolved |
| Deadlock / MainActor | Low if worker ownership and callback reentrancy are explicit |
| Thread starvation | Bounded by a small worker pool; each blocked call consumes a worker |
| Nested `java.ajax` | Sequential reentrant host calls work on the same worker; recursive runtime entry must be rejected or depth-limited |
| WebView / future services | WebView stays in a separate async/MainActor service and is not forced into this worker |
| Migration cost | Moderate and localized to the future runtime layer |

Decision: choose this as the target architecture, subject to finding and testing
a public, cancelable synchronous Apple transport implementation. The transport
cannot be synthesized by blocking the existing async client.

## Option C: synchronous transport directly inside the current adapter

Inject a synchronous network client into
`JavaScriptCoreRuleJavaScriptExecutor` and let it block whichever thread called
`RuleExecutor.execute`.

| Concern | Assessment |
| --- | --- |
| Android synchronous JS semantics | High |
| Existing RuleExecutor | Small code change |
| HTTPClient | Either duplicated or wrapped unsafely |
| Windows tests | Easy with a fake |
| JavaScriptCore | Easy callback shape |
| Cancellation / timeout | Depends completely on transport |
| Deadlock / MainActor | Unacceptable: ordinary callers can block the UI or cooperative executor |
| Thread starvation | Unbounded because call-site execution context is uncontrolled |
| Nested `java.ajax` | Possible but magnifies blocking/reentrancy hazards |
| WebView / future services | Poor separation |
| Migration cost | Low initially, high when production call sites must be repaired |

Decision: reject for production. An immediate in-memory mock host may use the
same synchronous call shape in tests, but the adapter must not accept the async
HTTP client or claim network readiness.

## Option D: Promise bridge or source transformation

Expose `java.ajax` as a Promise, require scripts to use `await`, or rewrite
arbitrary source scripts into resumable code.

This has good async transport behavior but changes the observable Android API.
Existing scripts expect `JSON.parse(java.ajax(url))`, string concatenation, and
immediate response methods. JavaScriptCore has no general public API that
automatically suspends and resumes an arbitrary native callback. Source
transformation would need a complete JavaScript parser and continuation
transform and would still be incompatible with native object/reflection calls.

Decision: reject for Android-compatible rules. Promise APIs may be offered as a
new non-Legado extension later, but cannot implement the legacy methods.

## Chosen architecture and current gate result

The target is Option B:

```text
BookSource/Search/TOC/Content runtime (future, async)
  -> bounded JavaScriptExecutionWorker (dedicated native threads)
  -> synchronous RuleExecutor and isolated JSContext
  -> allowlisted synchronous RuleJavaScriptHost
  -> true cancelable synchronous transport (not HTTPClient blocking)
  -> shared HTTPRequest / HTTPResponse models and request semantics
```

The architecture gate is currently **closed for production network I/O**.
Neither Foundation's existing async `HTTPClient` nor public JavaScriptCore APIs
provide the missing safe synchronous callback boundary. No production
`java.ajax/get/post/head` transport will be added in this phase.

This phase may safely add:

- platform-neutral, synchronous host call contracts whose documentation
  requires dedicated-worker use for any blocking implementation;
- immutable response snapshots;
- per-execution request/body/result budgets;
- deterministic fake-host tests;
- an optional JavaScriptCore allowlist wired only to an injected immediate host
  such as a test mock.

It must not add `DispatchSemaphore`, `NSCondition`, RunLoop polling, sleep/poll
loops, `Task` plus synchronous waiting, or any `sendSync` wrapper around
`HTTPClient`.

## Host and response contract

The Core host surface has exactly four methods: `ajax`, `get`, `post`, and
`head`. Parameters and results contain only Swift value snapshots. It does not
reference `JSContext`, `JSValue`, `URLRequest`, `URLSession`, WebKit, or Android
objects.

`ajax` returns an optional string. `get/post/head` return an immutable
`JavaScriptHTTPResponseSnapshot` exposing the reader subset proven useful by
the Android interface: body, status, headers, cookies, final URL, content type,
charset, and method. JavaScriptCore constructs a pure JavaScript wrapper with
methods such as `body()`, `statusCode()`, and `header(name)`; the Swift response
struct itself is never exported for reflection.

The optional Apple host is initializer-injected. With no host, no `java` object
is installed, preserving the pure-JavaScript executor and making unsupported
host use explicit. Every evaluation still creates a new `JSContext` and a new
call budget. No cookies, variables, or response wrappers persist across rules.

## Resource limits

Foundation defaults for the host contract are:

- 16 network calls per JavaScript execution;
- 1 MiB UTF-8 POST body per call;
- 8 MiB UTF-8 response body per call.

Sixteen permits ordinary pagination/token flows while bounding accidental
loops. One MiB is far above typical form/JSON source requests. Eight MiB covers
large HTML/JSON chapters without permitting an unbounded in-memory response.
All values are explicit and configurable. The budget is owned by one execution,
so separate contexts and concurrent executors do not share counters.

These are application safety limits, not Android behavior. Android has no
equivalent per-script request budget on these methods. A later transport should
also enforce raw compressed/uncompressed byte limits before decoding; the
foundation snapshot currently measures its deterministic UTF-8 representation.

## Timeout, cancellation, and infinite loops

The future worker/transport must provide request timeout and cancellation at the
transport level and must reject recursive entry into the same runtime (or apply
a documented nesting limit). Cancellation of an HTTP request does not imply
termination of the surrounding JavaScript evaluation.

No documented public Apple JavaScriptCore API was found for forcibly
interrupting a running `JSContext.evaluateScript`. Therefore a pure script such
as `while (true) {}` still cannot be safely terminated in-process. The existing
input/result/container limits and the new host request budget reduce other
resource risks but do not solve CPU-bound infinite loops. Production execution
of untrusted third-party scripts remains gated until the project chooses a
stronger isolation strategy (for example, a separately killable process where
platform policy permits it) or Apple publishes a suitable API. Private symbols
must not be used.

## Future migration

The next runtime phase should prototype the bounded worker and transport as a
separate component, demonstrate cancellation and MainActor non-blocking tests,
then reuse `RequestBuilder` semantics for AnalyzeUrl-style `ajax`. Because the
current builder and cookie store are async, reuse may require extracting pure
request parsing from async cookie loading rather than waiting on the existing
method. `get/post/head` need their own jsoup-compatible behavior: no redirects,
no automatic source headers/cookies, and status errors thrown.

WebView, `webJs`, login, browser DOM, source/book/chapter bindings, persistent JS
state, Android reflection, and complete Rhino parity remain separate stages.
