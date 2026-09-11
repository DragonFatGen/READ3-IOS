# Live source compatibility CLI

## Purpose

`legado-compatibility` is a cross-platform, manually invoked diagnostic for a
local Legado book-source JSON file. It composes the production
`BookSourceCompatibilityRunner`, `URLSessionHTTPClient`, request builder,
selectors, runtimes, and text decoder to execute:

```text
Import -> Search -> BookInfo -> TOC -> Content
```

It reports only a bounded summary. It never prints the source JSON or chapter
text. Compatibility remains limited to the documented and tested Legado subset.
Cookies received during a run are kept only in an in-memory production cookie
session and are neither persisted nor included in output.

## PowerShell 7 usage

Human-readable output:

```powershell
swift run --package-path Packages/LegadoCore legado-compatibility `
  --source .\my-source.json `
  --keyword "三体"
```

JSON summary:

```powershell
swift run --package-path Packages/LegadoCore legado-compatibility `
  --source .\my-source.json `
  --keyword "三体" `
  --json
```

The source path and keyword are required. The file must contain a single source
object (including supported legacy formats); arrays of sources are not accepted.
Optional arguments are:

| Argument | Default | Validation |
| --- | ---: | --- |
| `--search-page` | `1` | At least 1 |
| `--book-index` | `0` | Zero-based, not negative |
| `--chapter-index` | `0` | Zero-based, not negative |
| `--maximum-page-count` | `100` | Between 1 and 500 |
| `--json` | off | Emits the dedicated Codable summary DTO |
| `--help` | | Displays command help |

The summary contains stage and count information, the selected book/author and
chapter names, and the number of Swift characters in successfully parsed
content. It does not contain response bodies.

## Exit codes

| Code | Meaning |
| ---: | --- |
| `0` | The complete chain succeeded |
| `1` | Compatibility, parsing, selection, or network execution failed |
| `2` | Arguments, source-file reading, JSON syntax, or source import were invalid |

Failure categories, operations, and messages come from the compatibility
runner, which redacts common authorization, cookie, password, secret, and token
forms and limits diagnostic length. The shared public
`BookSourceCompatibilityRunner.redacted(_:)` also bounds CLI names and error
messages to 500 characters. Sensitive assignments hide the rest of their line
to cover multi-part credentials. This is a diagnostic filter, not a tool for
sanitizing response bodies or arbitrary private data. Argument errors do not
echo untrusted argument values. `--help` exits with code 0.

## Network and fixture policy

Running this command performs real network requests and is always optional and
manual. The dedicated GitHub Actions workflow described below runs it only when
manually dispatched. Regular Core Tests never use live sources; they use
`MockHTTPClient`, temporary source files, and repository fixtures.

When a live run exposes a compatibility gap, save only the minimum response
fragment needed to reproduce it, remove domains and account identifiers, strip
headers and cookies, replace book text with invented short Chinese text, and
add the result under `TestSources` with deterministic expectations. Review the
fixture before committing it.

Never commit private source collections, credentials, cookies, authorization
headers, login form values, tokens, downloaded books, or copyrighted chapter
content. Do not paste them into bug reports or CLI output.

## Manual GitHub Actions diagnostic

No local Swift installation is needed. The **Manual Source Diagnostic** workflow
(`.github/workflows/source-diagnostic.yml`) uses `workflow_dispatch` only: no
push, pull-request, or scheduled live runs. A single dispatch starts independent
Windows (`windows-2022`, existing Swift 6.3.3 setup) and macOS (`macos-15`, runner
Xcode Swift as in Core Tests) jobs, with read-only repository permissions.
The matrix uses `fail-fast: false`: failure on either platform does not cancel
the other. Both receive the same `SOURCE_DIAGNOSTIC_JSON` Secret and all five
dispatch inputs, with unchanged defaults. Do not rotate the Secret during a run.

1. In the repository, open **Settings → Secrets and variables → Actions → New
   repository secret**. Name it `SOURCE_DIAGNOSTIC_JSON` and paste the original
   JSON for **one source object**, not an array or a URL. Use a source you are
   authorized to test, without login, CAPTCHA or WebView requirements. Do not
   commit the source file. This setup must be performed by the repository owner;
   development of the workflow does not create a Secret or trigger a live run.
2. Open **Actions → Manual Source Diagnostic → Run workflow**, select the trusted
   `main` branch, and enter a keyword. The keyword is an ordinary workflow input,
   visible in run metadata; do not put passwords or other sensitive data in it.
3. Keep `search_page=1`, `book_index=0`, `chapter_index=0` for a small initial
   sample. `maximum_page_count` defaults to **3** and accepts **1–10**. Page must
   be at least 1; indices must be nonnegative integers (at most 2147483647).
   Keywords must be nonblank, at most 200 characters, without control characters
   or a leading `--`. Blank/invalid inputs and a missing Secret fail explicitly.
4. Wait for both **Source diagnostic / Windows** and **Source diagnostic / macOS**.
   View the platform-labelled **Summary** sections and download
   **source-diagnostic-report-Windows** and **source-diagnostic-report-macOS**
   from **Artifacts**. Each archive contains its own `report.json`; extract them
   into separate directories. Artifacts expire after **3 days**. Only sanitized
   JSON is uploaded; the original source is never an artifact.

### Comparing the two reports

Each report includes an `environment` object: `platform`, `architecture`,
`toolchain` and the actual numeric `swiftVersion`, obtained with `swift --version`
before the Secret is supplied. The check requires Swift 6.0 or newer (the package
manifest minimum). Unknown version output fails setup without publishing raw
output. A null version means setup/version verification was unavailable.
macOS uses the runner's selected Xcode toolchain, which can change with runner
image updates; it is not claimed to match Windows Swift 6.3.3. Both summaries
explicitly flag this comparison limitation. Even matching release numbers do
not imply identical compiler builds, Foundation implementations or architecture.

Compare reports from the **same dispatch/commit** in this order:

1. Check environment versions and architectures. Record differences alongside
   the outcome; a different toolchain is a possible confounding factor.
2. Check `status`, `completedStage`, `failureCategory` and `failureOperation`.
   A setup/build failure is not a source or network diagnostic.
3. Compare `requestFailureKind`, `networkErrorDomain`, `networkErrorCode`,
   `httpStatusCode` and the fixed `requestFailureSummary`, followed by result
   counts when available. Null HTTP status is not HTTP 0.

The supplied evidence for run **34457502916** is `unknown`, `NSURLErrorDomain`,
code `-1`, null HTTP status at the search request stage. It does not establish
the root cause. Success on macOS and failure on Windows would narrow the
investigation, but would not alone prove an OS bug: toolchains, runner networks,
egress addresses, timing and changing site results can differ. Equal failures
also do not establish a specific cause. The jobs use independent in-memory
cookie sessions. This comparison does not change source parsing, certificate
validation or retry policy.

The runner builds the existing executable, then invokes it directly with an
argument list, preserving separate stdout, stderr and exit status. Source JSON
is written unchanged as UTF-8 without a BOM into the runner's private temporary
directory after the build succeeds. Inputs and the Secret enter the script via
environment variables, never interpolated shell source. The Secret is removed
from the environment before starting child processes. Build and CLI raw output
are private temporary files, deleted in `finally` and an `always()` cleanup step.
Forced runner termination can prevent cleanup; GitHub-hosted ephemeral runners
are used, not persistent self-hosted machines.

The public report contains only a fixed run status, boolean success, allowlisted
business stages/categories, nonnegative counts, fixed explanations, and the
optional structured request metadata described below, plus validated platform
and toolchain metadata. Raw Swift version output is not published.
Book/author/chapter names and the CLI's free-form `errorMessage` are discarded.
This intentionally sacrifices error detail: generic redaction cannot prove that
URLs, query strings, credentials or arbitrary private variables are absent.
Raw stderr, responses, headers, cookies, source objects and content are never
uploaded or echoed. Summary values are HTML-escaped text inside a fixed block.

Successful CLI exit `0` requires a valid, consistent success report. Exit `1`
(compatibility/network failure) or `2` (input failure) remains a failed job after
summary generation and upload. Malformed output, timeout or process failure
also fails. Build/setup failures have their own fixed summaries with **null**
business metrics, not invented search/content results. The job timeout is 25
minutes, with a 10-minute CLI build limit and a 3-minute diagnostic limit.

`Scripts/Tests/SourceDiagnostic.Tests.ps1` tests validation, stream/argument
isolation, exit codes, schema filtering and summary escaping offline in the
Windows and macOS Core Tests jobs and both manual diagnostic jobs. It uses
synthetic text and a local PowerShell child process, never the Repository
Secret, Swift execution or a website.
Tests also cover executable naming, Swift version filtering, paths with spaces
and Unicode, setup-failure publication and explicit cleanup. Path construction
uses `Join-Path` and .NET temporary directories; the CLI has an `.exe` suffix
only on Windows. Both platforms use the same shell-free process argument list
and private stdout/stderr capture.
Existing XCTest tests continue to cover CLI and runtime business behavior.

A successful report indicates only that the chain produced results during that
run. It does not independently prove semantic correctness, permanent website
availability or complete Legado compatibility. Keep any detailed investigation
private and convert only minimal, reviewed, invented-text fixtures into tests.

## Structured request diagnostics

Request failures now carry optional metadata from `URLSessionHTTPClient` through
the search/book-info/TOC/content runtime errors, `CompatibilityFailure`, and the
CLI JSON DTO. Previously the HTTP client converted the underlying error to a
string, runtimes retained only localized text, and PowerShell discarded that
free-form text in favor of the fixed `request` category summary. The historical
run [34450232880](https://github.com/DragonFatGen/READ3-IOS/actions/runs/34450232880)
at `9c170c0` therefore does not establish a DNS, TLS, timeout or construction
cause. These fields cannot retroactively recover its missing metadata.

| Field | Meaning |
| --- | --- |
| `requestFailureKind` | `requestConstruction`, `dns`, `connection`, `tls`, `timeout`, `cancelled`, `otherNetwork`, or `unknown` |
| `networkErrorDomain` | Allowlisted system domain: `NSURLErrorDomain`, `NSPOSIXErrorDomain`, or `NSOSStatusErrorDomain`; otherwise absent |
| `networkErrorCode` | Signed numeric code in that domain; absent when the domain is not allowlisted |
| `httpStatusCode` | HTTP status of the response accompanying the failed transfer, if one actually exists; otherwise absent |
| `requestFailureSummary` | Additional fixed explanation generated by PowerShell from `requestFailureKind`; never copied from CLI free-form text |

The first four fields are optional CLI JSON fields. PowerShell includes all five
as values or `null` in the public artifact and escaped Step Summary. Old reports
without the new fields remain valid. Existing fields, `errorSummary`, and exit
codes are preserved. Invalid new enum/domain/value types fail report validation
instead of publishing untrusted data. No workflow or Secret changes are needed.

`requestConstruction` identifies the request-builder boundary (URL, headers,
options or encoding), or URLSession's bad/unsupported URL codes. It does not
identify which source field is wrong. Recognized URL error codes distinguish
host resolution, connection loss/unavailability, TLS/certificate failures,
timeouts, cancellation and other network errors. Classification never examines
localized descriptions. Unrecognized codes, custom errors and POSIX/OSStatus
errors retain `unknown`; safe system domain/code metadata remains available for
subsequent investigation. Custom domain strings and their codes are omitted
because domains can contain private data.

An absent HTTP status does not mean HTTP 0, nor does it prove that the server
never saw the request. The status is captured only from the response supplied
with the failed URLSession completion, never a previous request or redirect.
This is failure metadata, not a history of all successful responses or downstream
parsing failures. Non-2xx responses still follow the existing retry and body
parsing behavior; this diagnostic change does not turn them into exceptions.
Request failure messages in the compatibility report use fixed text; raw
NSError descriptions, `userInfo`, URLs, headers and bodies are not added to
diagnostic output.

Deterministic Core/CLI tests construct errors and inject mock responses; the
existing Windows Core Tests job also runs the PowerShell whitelist tests.
No tests added for this change contact websites. Compilation and test execution
must be verified by GitHub Actions for the new commit, not inferred from earlier
successful builds.

## Search-stage diagnostics

`searchDiagnostic` is an optional, safe object in the CLI JSON and the sanitized
PowerShell report/Step Summary. Old reports without it remain accepted and
publish `searchDiagnostic: null`. New nested counts and booleans are explicitly
null when their stage has not run or a complete measurement is unavailable.
The runtime overload `search(source:keyword:page:diagnostic:)` updates an inout
`SearchDiagnostic` even when it throws, without changing existing return values
or error types. The runner carries it through later stages and adds selection
metadata. It contains no source, rule, URL, header, body, title or error text.

**The existing `searchResultCount` retains its historical meaning:** the length
of the successfully returned array stored by the runner. A search exception
leaves that array at its default empty value, so old `0` does not prove a measured
zero. Use `searchDiagnostic.finalResultCount` to distinguish null (unfinished)
from 0 (a completed parse returned no valid results). `completedStage` still
describes the last completed business stage; successful parsing followed by
selection failure still leaves it at `import`.

| Nested field | Meaning |
| --- | --- |
| `lastStage` | Last entered boundary: `definition`, `requestBuild`, `request`, `responseDecode`, `bookList`, `fields`, `parsed`, `resultSelection` |
| `lastField` | Last visited field: `name`, `author`, `kind`, `wordCount`, `lastChapter`, `intro`, `coverUrl`, `bookUrl`; null before fields |
| `bookListMatchedCount` | Actual node collection size after successful bookList evaluation, before filtering; null if evaluation failed |
| `missingNameCount` | Entries rejected for an empty formatted name after a complete field pass; null if that pass was interrupted |
| `missingBookURLCount` | Entries with blank raw bookUrl extraction, before existing URL fallback; null if any node's bookUrl was skipped or field processing failed |
| `filteredItemCount` | Entries removed by existing filtering during a complete parse (currently empty names only) |
| `finalResultCount` | Complete returned result count; null on a thrown search error |
| `ruleThrew` | Whether bookList/field rule processing threw (including syntax and unsupported capability checks); null before rule processing |
| `ruleFailureCategory` | First observed rule error: `ruleParser`, `selector`, `javascript`, `unsupportedCapability`, `unknown`; null without a rule error |
| `requestedBookIndex` | Requested zero-based book index, recorded when search is attempted |
| `indexInRange` | Whether that index exists in the completed result array; null if parsing did not complete |
| `responseStatusCode` | Status of the search response actually returned by the HTTP client, or null before a response exists |
| `responseContentType` | Allowlisted MIME group: `html`, `json`, `text`, `xml`, `other`, `unknown`; parameters and raw header values are discarded |
| `responseByteCount` | Size of the returned response Data, before text decoding; not wire/compressed size |
| `responseRedirected` | Whether the returned response contains followed redirect hops; null without a response |
| `pageHint` | Advisory `searchForm`, `bookDetail`, `loginOrVerification`, or `unknown`; `other` is reserved/accepted but currently not inferred |

The existing top-level `httpStatusCode` remains **request failure metadata**.
It is not repurposed for successful transfers. Search response metadata can
therefore show status 200 while top-level network fields are null. Neither the
status nor the page hint changes existing status handling or retries. Metadata
describes the returned search response, not an entire request/redirect history.

Read a failed report as follows:

1. `definition` means no executable search definition or an already unsupported
   search-URL capability. `requestBuild` and `request` identify construction and
   transport failures; use the existing structured request fields for their
   known causes. Counts remain null.
2. `responseDecode` with a `charset` failure means the response arrived but
   decoding failed. Response size/type/status survive, list counts remain null.
3. `bookList` with `ruleThrew=true` identifies failed list parsing/evaluation.
   A null match count is not a zero match.
4. `fields` with a known match count identifies an interrupted field pass;
   `lastField` shows the field being processed. Full-pass counts remain null.
5. `resultSelection` with `bookListMatchedCount=0` means the list rule completed
   with no matching nodes. Positive matches plus a zero final count and positive
   `filteredItemCount` mean nodes were rejected during field extraction.
6. Positive `finalResultCount` with `indexInRange=false` means results exist but
   the requested index is outside them. `indexInRange=true` means selection
   succeeded; subsequent failures belong to later business stages.

Existing parser behavior is intentionally preserved: empty names filter only
that entry; empty book URLs resolve to the response base URL and are **not**
filtered. Fields after an empty name are not evaluated. Thus the missing-URL
total is unknown when even one name-filtered node skipped its URL rule. A
required-field rule exception aborts the search. Optional-field exceptions that
the existing parser tolerates still return nil for that optional field; they
now set `ruleThrew=true` without making the search fail. The first error category
can therefore describe an earlier tolerated error, while `lastField` records
the last field visited. Unknown error types stay `unknown`; classification does
not inspect localized messages. Search failures in CLI `errorMessage` now use
fixed text as well; PowerShell retains its existing fixed `errorSummary`.

Page hints use a separate bounded HTML probe (at most 262,144 UTF-8 bytes, only
when the normalized content type is HTML). A search form has an explicit search
role or search input; a detail hint requires book Open Graph type/title metadata
and an h1; a login hint requires password and username/email inputs in the same
form. A URL containing `action=login` alone has no effect. Conflicting structural
signals, unrecognized layouts, oversized/non-HTML pages and probe failures stay
`unknown`. A shared login/search widget can resemble these signals: hints do
not establish that login is required, that the page is correct, or that the
source is compatible. The probe never changes rule execution.

The supplied report for run **34567224481**, commit **f983a88**, has identical
Windows/macOS `import` completion, `search` failure and legacy count 0, with
empty network metadata. It lacks these new observations; it cannot identify
the matching/filtering/selection boundary by itself. The current 速读谷 candidate
has **not passed** the Swift CLI diagnostic. The independent observation that a
full-title HTTP search returned a detail page does not prove Actions received
the same page. No source-specific rule, parsing semantic, TLS or retry change
is justified by this report alone.

After pushing the new commit, first check Windows/macOS **Core Tests**, which
compile the package and run XCTest plus the offline PowerShell tests. Then
manually dispatch **Manual Source Diagnostic** on `main` using the existing
Secret and the same public inputs: keyword `苟在两界修仙`, `search_page=1`,
`book_index=0`, `chapter_index=0`, `maximum_page_count=5`. Compare both platform
artifacts from that dispatch, starting with environment/toolchain metadata and
then `searchDiagnostic`. Development does not read/change the Secret or trigger
this live run. Offline tests use invented HTML, mock responses and injected
errors, including direct detail results, zero-match forms, missing fields,
rule failures, out-of-range selection, and rejection of sensitive report fields.

## Known limitations

The command cannot make an unstable third-party site deterministic. WebView
login, persistent authenticated sessions, and production rule-side
`java.ajax/get/post/head` remain unsupported by the compatibility runner. A
diagnostic failure therefore identifies the reached boundary; it does not by
itself prove that the source is invalid or that full Legado parity exists.
