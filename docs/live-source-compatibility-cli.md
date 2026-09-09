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
manual. GitHub Actions does not invoke it against real websites. Required tests
use `MockHTTPClient`, temporary source files, and repository fixtures.

When a live run exposes a compatibility gap, save only the minimum response
fragment needed to reproduce it, remove domains and account identifiers, strip
headers and cookies, replace book text with invented short Chinese text, and
add the result under `TestSources` with deterministic expectations. Review the
fixture before committing it.

Never commit private source collections, credentials, cookies, authorization
headers, login form values, tokens, downloaded books, or copyrighted chapter
content. Do not paste them into bug reports or CLI output.

## Known limitations

The command cannot make an unstable third-party site deterministic. WebView
login, persistent authenticated sessions, and production rule-side
`java.ajax/get/post/head` remain unsupported by the compatibility runner. A
diagnostic failure therefore identifies the reached boundary; it does not by
itself prove that the source is invalid or that full Legado parity exists.
