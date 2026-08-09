# Legado rule syntax: parser boundary and IR

This document records observable behavior from Android Legado commit
`c043ea72fd2698d27a7dcbc0beb7844c572e544c`, the gitlink currently pinned by
`Reference/READ3.0`. The submodule was not initialized in the worktree; analysis
used a detached, read-only checkout in the system temporary directory. No file
under `Reference/READ3.0` was changed.

## Android evidence

Primary files, relative to the Android repository:

- `app/src/main/java/io/legado/app/model/analyzeRule/AnalyzeRule.kt`
  - `splitSourceRule`: splits `<js>...</js>` blocks and an `@js:` remainder into
    sequential `SourceRule` objects.
  - There is no standalone `SourceRule.kt` in this pinned revision; `SourceRule`
    is the inner class at `AnalyzeRule.SourceRule`.
  - `SourceRule.init`: recognizes explicit and inferred selector modes, removes
    `@put`, identifies `@get`, `{{...}}`, capture references, and `##` replacement
    fields.
  - `SourceRule.makeUpRule`: evaluates dynamic parts first, then splits `##` into
    selector, pattern, replacement, and replace-first marker.
  - `replaceRegex`: executes replacement later; invalid regex falls back to
    literal string replacement.
  - `getString`, `getStringList`, `getElement`, and `getElements`: consume the
    sequential `SourceRule` list and dispatch by mode.
- `app/src/main/java/io/legado/app/model/analyzeRule/RuleAnalyzer.kt`
  - `splitRule`: balanced splitter for `&&`, `||`, `%%`, and `@`.
  - `chompRuleBalanced` / `chompCodeBalanced`: protect operators inside brackets,
    parentheses, and quoted text. Backslash escaping differs between selector
    and code modes.
  - `innerRule`: replaces embedded JSONPath-style expressions.
- `AnalyzeByJSoup.kt`
  - `SourceRule`: strips `@CSS:` and selects explicit CSS mode.
  - `getElements` / `getResultList`: interpret `@` as a left-to-right child
    selection chain for historical JSoup rules. Explicit CSS retains `@` for
    CSS/attribute syntax instead.
- `AnalyzeByJSonPath.kt` and `AnalyzeByXPath.kt`
  - string/list/element functions apply `&&`, `||`, and (for lists) `%%` with
    the result-combination behavior below.
- `AnalyzeByRegex.kt`
  - all-in-one element rules use `&&` as a chain of extraction regex patterns.
- `app/src/main/java/io/legado/app/constant/AppPattern.kt`
  - `JS_PATTERN` is case-insensitive
    `<js>([\w\W]*?)</js>|@js:([\w\W]*)`; therefore `@js:` consumes the rest.
- `app/src/main/java/io/legado/app/model/webBook/BookList.kt`
  - `analyzeBookList` calls `getElements`; field rules are pre-split through
    `splitSourceRule` and reused by `getString`/`getStringList` per item.

Additional calls in `BookInfo`, `BookChapterList`, `BookContent`, and RSS parsing
follow the same `AnalyzeRule` entry points. They change result shape and URL
normalization, not the syntax recognized in this parser phase.

The traced production flow is `BookList.analyzeBookList` / `BookInfo.analyzeBookInfo`
/ `BookChapterList.analyzeChapterList` / `BookContent.analyzeContent` /
`RssParserByRule.parse` -> `AnalyzeRule.getElements` for collection rules ->
`splitSourceRule` plus `getString` or `getStringList` for fields. Those entry
points dispatch to `AnalyzeByJSoup`, `AnalyzeByJSonPath`, `AnalyzeByXPath`, or
`AnalyzeByRegex`; JavaScript stages dispatch to `evalJS`.

## Prefixes and inferred types

| Syntax | Android meaning | IR |
| --- | --- | --- |
| no prefix | historical JSoup selector syntax | `selector(.legado, value)` |
| `@CSS:` | explicit JSoup CSS selector; prefix removed by `AnalyzeByJSoup` | `selector(.css, value)` |
| `@@` | force historical/default selector and remove the two `@` characters | default selector |
| `@XPath:` | explicit XPath | `xpath` |
| leading `/` | inferred XPath | `xpath` |
| `@Json:` | explicit JSONPath | `jsonPath` |
| leading `$.` or `$[` | inferred JSONPath | `jsonPath` |
| JSON response context | unprefixed rules default to JSONPath | `RuleParseContext.contentIsJSON` |
| `<js>...</js>` | JavaScript stage embedded in the source-rule pipeline | `javaScript` in `sequence` |
| `@js:` | JavaScript from the prefix through end of rule | `javaScript` |
| leading `:` in all-in-one element context | extraction-regex mode; persists in Android's mutable analyzer | `regex(.extraction)` with explicit context only |

Prefix comparisons are case-insensitive where Android uses `startsWith(...,
true)` or a case-insensitive pattern. Unknown `@name:` text remains a historical
selector; Android has no generic unsupported-prefix error.

The old/new syntax boundary is therefore behavioral rather than versioned:
historical JSoup rules use `@` chains and tag/class/id shortcuts, while newer
explicit forms add `@CSS:`, `@XPath:`, and `@Json:`. `@@` preserves a way to
force historical/default handling when leading characters would otherwise be
interpreted as a type prefix.

## Operators and combination order

The operators combine extraction results; they are not Boolean operators:

- `&&`: evaluate every branch and append non-empty results in rule order.
- `||`: evaluate branches in rule order and stop after the first non-empty result.
- `%%`: evaluate branches and interleave their list results by index, using the
  first non-empty result's length as the outer bound.
- `@`: in historical JSoup mode, feed each selected element set into the next
  child selector. It is not the same operation as `&&`.
- `##`: after templates and capture substitutions, field 0 is the selection
  rule, field 1 the regex pattern, field 2 the replacement, and presence of a
  fourth field enables replace-first mode. It is not a selector combination.
- In all-in-one regex extraction mode only, `&&` chains regex passes: all matches
  from one pattern are concatenated and become input for the next pattern.

There is no fixed conventional precedence table. `RuleAnalyzer.splitRule` takes
the first top-level occurrence among the candidate operators as the operator for
that recursion level, splits later occurrences of that same operator, and each
branch is parsed recursively. Consequently `a&&b||c` groups as
`a && (b || c)`, while `a||b&&c` groups as `a || (b && c)`. Branch order is
always left to right. `##` is separated at the `SourceRule` layer and JavaScript
stages are separated before selector dispatch.

## Balancing, escaping, and tolerance

`RuleAnalyzer` protects separators inside `[...]` and `(...)`. Both balancing
modes recognize single and double quotes. Selector mode treats backslash as an
escape only outside quotes; code mode treats backslash as an escape generally
and additionally balances square brackets against the active group. An
unbalanced selector/filter group throws an Android `Error`.

Android does not provide a general escape for `##`: `makeUpRule` uses a literal
split after dynamic substitution. Similarly, all-in-one regex extraction uses a
literal `&&` split, so a pattern containing that sequence becomes multiple
extraction stages.

Compatibility behavior preserved by the Swift parser:

- empty input becomes `.empty`;
- empty `&&`/`||`/`%%` branches are retained in compatible mode;
- an unterminated `{{` is retained as literal template text because Android's
  non-greedy matcher does not recognize it;
- an unterminated `<js>` is ordinary selector text;
- regex patterns are not compiled by the parser, so malformed patterns remain
  structural data for the future executor;
- unknown prefixes remain selectors.

`RuleParseContext.ErrorPolicy.strict` optionally reports unterminated templates
and empty combination branches. This is diagnostic tooling, not the default
Android-compatible behavior. `RuleSyntaxError.malformedRegex` and
`unsupportedPrefix` exist for a future validator profile, but the parser does
not emit them because doing so would tighten Android behavior without evidence.

## Templates and dynamic phase

`{{...}}` is processed by `SourceRule.makeUpRule` before selector dispatch and
before `##` fields are finalized. A body beginning with `@`, `$.`, `$[`, or `//`
is recursively treated as a rule; every other body is JavaScript. Literal text
around one or more bodies is retained. Empty bodies are JavaScript with an empty
source string. Android's matcher is non-greedy and does not match an unclosed
body.

The Swift IR stores these pieces as `TemplateExpression.Part`. It deliberately
does not evaluate them. Operators produced dynamically by a template belong to
the future execution/expansion phase; the static parser protects operators in a
template body from being mistaken for surrounding combinations.

## Swift implementation strategy

`RuleParser.parse(_:context:)` is a pure `String -> RuleExpression` operation.
The order is:

1. separate `<js>` blocks and an `@js:` remainder into a sequential pipeline;
2. recognize explicit all-in-one regex context;
3. separate structural `##` replacement fields while protecting templates;
4. structure templates without evaluating them;
5. find the first balanced top-level result-combination operator and recurse;
6. recognize prefixes/inferred selector type and historical `@` child chains.

The parser has no global state. Android's mutable `isJSON` and persistent
`isRegex` flags are represented by immutable `RuleParseContext` values, which
prevents one parse call from contaminating another.

A separate executor now supplies result-shape-specific behavior for combinations,
templates, sequence, variables, captures, and regex. Concrete selector engines
remain behind an injection boundary and are not part of the parser or this
foundation executor.

## Current execution boundary

Sequence, `&&`/`||`/`%%`, templates, regex extraction/replacement, `$n` capture
references, and `@put`/`@get` now have execution behavior and dedicated IR where
needed. Regex compilation remains an execution-stage operation.

Historical/default, explicit CSS, JSONPath, and the documented XPath subset
execute when `LegadoRuleSelectorExecutor` is injected. JavaScript, network,
WebView, persistence, and UI remain out of scope. Selector compatibility
boundaries are documented in `docs/rule-jsoup.md`, `docs/rule-jsonpath.md`, and
`docs/rule-xpath.md`.

The dynamic boundary follows Android `makeUpRule`: a rule-shaped body inside
`{{...}}` is recursively parsed and evaluated, but the completed outer template
string is not classified a second time. Operators produced by expansion remain
text rather than becoming a new combination tree.
