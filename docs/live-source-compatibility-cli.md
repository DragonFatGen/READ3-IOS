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
push, pull-request, or scheduled live runs. It uses the same Windows runner and
Swift setup as Windows Core Tests, with read-only repository permissions.

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
4. View the job's **Summary** and download **source-diagnostic-report** from
   **Artifacts**. Artifacts expire after **3 days**. Only the sanitized JSON is
   uploaded; the original source is never an artifact.

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
business stages/categories, nonnegative counts, and a fixed category explanation.
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
existing Windows Core Tests job. It uses synthetic text and a local PowerShell
child process, never the Repository Secret, Swift execution or a website.
Existing XCTest tests continue to cover CLI and runtime business behavior.

A successful report indicates only that the chain produced results during that
run. It does not independently prove semantic correctness, permanent website
availability or complete Legado compatibility. Keep any detailed investigation
private and convert only minimal, reviewed, invented-text fixtures into tests.

## Known limitations

The command cannot make an unstable third-party site deterministic. WebView
login, persistent authenticated sessions, and production rule-side
`java.ajax/get/post/head` remain unsupported by the compatibility runner. A
diagnostic failure therefore identifies the reached boundary; it does not by
itself prove that the source is invalid or that full Legado parity exists.
