# Legado rule executor foundation

This execution contract is based on Android Legado commit
`c043ea72fd2698d27a7dcbc0beb7844c572e544c`. Analysis used a detached, read-only
checkout in the system temporary directory; `Reference/READ3.0` was not changed.

## Android evidence

`AnalyzeRule.getString`, `getStringList`, `getElement`, and `getElements` feed a
stage result into the next `SourceRule`. A null result stops later stages, while
an empty string is still a value. Swift therefore distinguishes `.none`,
`.string("")`, and `.strings([])`.

The JSoup, JSONPath, and XPath analyzers implement result combinations as follows:

- `&&` appends every non-empty branch in source order.
- `||` returns the first non-empty branch.
- `%%` retains non-empty branches and interleaves by index. The first retained
  branch supplies the outer index range; shorter branches are skipped and longer
  later branches are truncated to that range.

`SourceRule.makeUpRule` expands `$1`-style capture references, `@get:{key}`, and
`{{...}}` before separating `##` fields. Capture zero is the entire match.
Compatible execution retains an unavailable `$n` reference; strict execution
diagnoses it.

Template bodies beginning with `@`, `$.`, `$[`, or `//` become a nested
`SourceRule`; other bodies are JavaScript. This phase does not execute
JavaScript. An empty JavaScript body contributes no text, and a non-empty body
is explicitly unsupported. Android does not reclassify the fully expanded outer
string, so dynamically generated operators remain text.

`splitPutRule` removes case-insensitive `@put:{...}` objects. `putRule` evaluates
each string value as a rule before the main stage, and a later write replaces an
earlier value. Android selects chapter, book, then transient `RuleData` storage;
`@get` uses the same lookup order and returns `""` when absent. Swift models
durable inputs as `sourceVariables` and per-context writes as
`temporaryVariables`, with temporary values taking precedence. Contexts share
no global state. Chapter/book persistence remains deferred.

`AnalyzeRule.replaceRegex` compiles patterns during execution. Normal mode
replaces all matches and supports `$0`, `$1`, and `$2`. Invalid patterns fall
back to literal replacement in compatible mode; strict mode reports
`invalidRegularExpression`.

Android `replaceFirst` has a nonstandard result: it finds the first match,
replaces within that matched substring, and returns only the transformed match.
Surrounding input is discarded. No match returns an empty string. The Swift
compatible executor preserves this behavior.

## Swift model and boundaries

`RuleExecutor` consumes `RuleExpression + RuleExecutionInput + inout
RuleExecutionContext` and returns `RuleExecutionResult`. Context contains the
base URL, current result, source and temporary variables, capture groups, and
compatible/strict policy. It has no HTTP, DOM, JavaScript, Apple-framework, or
singleton dependency.

Sequence feeds each result to the next expression. Combination branches receive
the same input. Regex replacement maps over string lists without collapsing the
shape. Regex extraction chains patterns like `AnalyzeByRegex`; the final pattern
emits group zero followed by captures for every match.

`RuleSelectorExecutor` is an injection boundary. `LegadoRuleSelectorExecutor`
routes historical/default and explicit CSS extraction to SwiftSoup, JSONPath to
the JSONValue evaluator, and XPath to the SwiftSoup-backed XPath subset. Without
an adapter, selector nodes still fail explicitly.

## Known differences and deferred work

- Android can persist very large chapter/book variables outside its map; this
  core foundation has no persistence adapter.
- Android template JavaScript can return numbers, objects, and lists; JavaScript
  is deliberately unsupported here.
- JSONPath and XPath support intentionally covers documented compatibility
  subsets. Their boundaries are recorded in `docs/rule-jsonpath.md` and
  `docs/rule-xpath.md`; JSoup/CSS behavior remains in `docs/rule-jsoup.md`.
- Foundation `NSRegularExpression` may differ from Java regex for obscure syntax;
  future compatibility fixtures should document any observed cases.
