# Real-source compatibility

## Purpose and baseline

Real-source compatibility is evaluated against observable behavior in the
read-only Android reference `Reference/READ3.0` at commit
`c043ea72fd2698d27a7dcbc0beb7844c572e544c`.

The reusable offline chain is:

```text
BookSource JSON -> Import -> Search -> BookInfo -> TOC -> Content
```

The goal is to expose general compatibility gaps in import, rule parsing,
selectors, request construction, charset handling, and runtime orchestration.
It is not a mechanism for source-specific patches.

## Android behavior used for comparison

Compatibility conclusions are taken from the Android model and runtime paths,
including `BookSource`, `AnalyzeUrl`, `AnalyzeRule`, `WebBook`, search analysis,
book-info analysis, TOC analysis, and content analysis. Before changing a
general Swift runtime behavior, the corresponding Android path must be checked
for field defaults, rule order, node context, URL bases, request options,
pagination, state propagation, and error behavior.

No compatibility fix may branch on source identity. Code equivalent to
`if sourceURL == ...`, `if sourceName == ...`, domain checks, source IDs, or
fixture-only switches is prohibited. A fix must describe a reusable Android
semantic and include regression coverage beyond the motivating fixture.

## Swift compatibility runner

`BookSourceCompatibilityRunner` accepts raw source JSON and composes the
existing production components:

1. `BookSourceImporter`;
2. `BookSourceSearchRuntime`;
3. `BookSourceBookInfoRuntime`;
4. `BookSourceTOCRuntime`;
5. `BookSourceContentRuntime`.

The runner does not reimplement selectors, requests, networking, charset logic,
or runtime rules. It receives the same injected protocols as the production
runtimes. Tests inject `MockHTTPClient`; fixture matching and assertions remain
in the test target rather than adding test branches to production runtimes.

`CompatibilityReport` retains every successfully produced intermediate result,
import warnings, migrations, and an optional failure. It intentionally does not
store request headers, cookies, passwords, tokens, login form values, or private
source variables.

`CompatibilityFailure` records both a specific category and the active business
operation. Supported categories are:

- `import`;
- `search`;
- `bookInfo`;
- `toc`;
- `content`;
- `request`;
- `charset`;
- `ruleParser`;
- `selector`;
- `javascript`;
- `unsupportedCapability`.

For example, a response-decoding failure during search is categorized as
`charset` with operation `search`. Diagnostic messages are length-limited and
redact common credential fields.

`CompatibilityReport.searchDiagnostic` separately retains safe search boundary
observations, including on thrown errors. See the [search diagnostic field
reference](live-source-compatibility-cli.md#search-stage-diagnostics) for null
count semantics, response metadata, advisory page hints and index validation.
This instrumentation does not change Android-compatible parsing or filtering.
The 速读谷 diagnostic candidate remains unverified by the Swift CLI; independent
HTTP observations and old zero-count reports are not compatibility proof.

## Offline fixtures and test coverage

The desensitized fixture under `TestSources/compatibility` contains a complete
BookSource JSON definition plus local search, book-info, TOC, and content
responses. It covers:

- real JSON import rather than a test-constructed `BookSource`;
- preservation of an unknown source field;
- a Chinese keyword encoded as a GBK GET parameter;
- mixed response bodies across the four network stages: GBK from HTTP charset,
  GB2312 from legacy HTML meta, undeclared GB18030 fallback, and Big5 recovered
  from HTML meta after an unknown HTTP declaration;
- relative book, TOC, and chapter URLs;
- malformed, unclosed content HTML recovered by the production selector;
- production Search -> BookInfo -> TOC -> Content hand-off;
- import, request, charset, rule-parser, selector, JavaScript, unsupported
  capability, TOC, and content failure reporting;
- diagnostic redaction;
- continued rejection of production `java.ajax/get/post/head`.

Existing deterministic runtime and selector suites additionally cover `@CSS`,
historical JSoup, JSONPath, XPath, regex replacement, templates, `@put/@get`, URL
options, GET/POST, headers/cookies, redirects, TOC pagination, content
pagination, and relative URL resolution. A compatibility report does not imply
that every syntax combination or Android source is supported.

Formal XCTest and CI execution must use `MockHTTPClient + fixtures`. Live site
responses are never fixed XCTest expectations.

## Optional live-network principle

The existing CLI can be run through the opt-in `workflow_dispatch` workflow
`source-diagnostic.yml` and its helpers under `Scripts`; see
[the CLI guide](live-source-compatibility-cli.md#manual-github-actions-diagnostic).
It stays outside required GitHub Actions live-network checks and reads a single
source from a Repository Secret. Its output is diagnostic or a candidate for a reviewed,
desensitized fixture. It must not write cookies, authorization headers, tokens,
accounts, passwords, or private source collections into the repository.

## Known differences

- Statistical response charset detection is not implemented.
- Complex selector and rule combinations outside current documented subsets may
  report `selector`, `ruleParser`, or `unsupportedCapability`.
- Runtime variables are isolated to the currently supported execution scope and
  are not persisted across application sessions.
- Fixture compatibility demonstrates deterministic behavior, not continued
  availability of any live website.

When a fixture reveals a gap, the required sequence is: verify Android source
behavior, document the general semantic, update the shared parser/selector/
request/charset/runtime implementation, and add deterministic regression tests.

## Explicitly unsupported capabilities

The following are deliberately outside this phase:

- WebView and `webJs`, because they require Apple UI/WebKit integration and a
  controlled browser security boundary;
- `loginCheckJs` and login-required sources, because login orchestration,
  credential storage, verification, and cookie synchronization are absent;
- production `java.ajax/get/post/head`, because synchronous rule execution does
  not provide the required asynchronous production network host and exposing an
  unrestricted bridge would violate the allowlist boundary;
- persistent variables, because no persistence ownership, isolation, or storage
  lifecycle has been defined;
- Reader UI, because this phase is limited to Core source compatibility;
- database and persistent cache behavior, because no DB/cache layer is in scope.

Encountering these capabilities produces `unsupportedCapability`. The runner
does not simulate, downgrade, or secretly implement them to make a fixture or a
particular source pass.
