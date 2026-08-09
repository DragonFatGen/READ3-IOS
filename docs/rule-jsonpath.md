# Legado JSONPath selector execution

This compatibility analysis is pinned to Android Legado commit
`c043ea72fd2698d27a7dcbc0beb7844c572e544c`. The source was read from a detached
checkout in the system temporary directory; `Reference/READ3.0` was not changed.

## Android implementation evidence

`AnalyzeByJSonPath.kt` uses `com.jayway.jsonpath.JsonPath` and `ReadContext`.
`app/build.gradle` pins `com.jayway.jsonpath:json-path:2.7.0`. The analyzer calls
the static `JsonPath.parse` default configuration. It does **not** use the
separate `JsonExtensions.jsonPath` parse context configured with
`Option.SUPPRESS_EXCEPTIONS`.

The default provider in this dependency returns Java maps, lists, strings,
numbers, booleans, and null. `getString` joins a list with newline and otherwise
uses Kotlin `toString()`. `getStringList` converts each list member separately,
or wraps one non-list result. Objects and nested arrays therefore use the JSON
provider's compact JSON form; boolean and null spellings are `true`/`false` and
`null`. `getObject` returns the raw result. `getList` requires an array result.

Missing paths, malformed paths, type mismatches, and malformed JSON throw from
Jayway. Android catches and debug-logs them in string/list extraction, producing
an empty result; `getObject` leaves the exception visible. READ3-IOS compatible
mode returns `.none`, while strict mode reports a typed `RuleExecutionError`.

`RuleAnalyzer` protects brackets, parentheses, quoted strings, and escapes when
separating Legado operators. It also expands one or more balanced `{$....}`
expressions in literal text. A failed or empty inner lookup is not substituted.
This project represents successful embedded forms as `jsonPathTemplate` IR;
the JSONPath adapter does not perform regex replacement or reparse `&&`, `||`,
`%%`, or `##`.

Automatic JSONPath selection occurs for explicit case-insensitive `@Json:`, a
leading `$.` or `$[`, or any unprefixed rule when the analyzer's JSON-content
flag is set. A bare `$` is valid Jayway JSONPath but is only automatically typed
in JSON-content context (or with `@Json:`).

## Syntax compatibility matrix

| Syntax | Android | Android result form | Swift plan/result | Full compatibility |
| --- | --- | --- | --- | --- |
| `$` | Yes | root object or root list | root; arrays flatten for string-list execution | Yes for string-list calls |
| `$.name` / bracket property | Yes | scalar/object/list | child selection and quoted properties | Yes |
| `$.books[0]` | Yes | selected value | array index | Yes |
| negative index | Yes | item counted from end | negative array index | Yes |
| `[*]` / `.*` | Yes | ordered list | wildcard | Arrays: yes; object key order is not guaranteed |
| `$..name` | Yes | ordered indefinite list | deterministic descendant-first named scan | Yes for the documented deterministic object ordering |
| `$..*` | Yes | indefinite list | recursive wildcard | Approximately |
| `[0,2]` | Yes | ordered union | index union | Yes |
| `['a','b']` | Yes | property projection | property union | Yes except object storage order |
| `[start:end]` | Yes | end-exclusive list | end-exclusive slice | Yes |
| negative slice bounds/step | Yes | Jayway slice behavior | supported subset | Approximately |
| `[?()]` | Yes | matching array members | existence, `!`, comparisons, `&&`, `||` | Partial |
| filter regex and operators (`=~`, `in`, `nin`, `subsetof`, etc.) | Yes | matching members | rejected explicitly | No |
| path functions (`length()`, `min()`, etc.) | Yes | function-specific scalar/list | rejected | No |
| multi-property / multi-index path | Yes | list | supported | Yes for covered forms |
| `{$...}` | Legado extension | literal plus inner `getString` | dedicated template IR | Yes for balanced successful substitutions |

## Swift library decision

No third-party JSONPath dependency is added. The candidates were assessed as
follows (repository activity was checked in August 2026):

| Candidate | License | SwiftPM / platforms | Syntax and Jayway fit | Maintenance / decision |
| --- | --- | --- | --- | --- |
| KittyMac/Sextant 0.4 | MIT | SwiftPM; claims Swift on Apple/Linux; no Windows CI or Swift 6 declaration | Broad JSONPath, originally derived from Jayway but explicitly documents later semantic divergence; uses its own Hitch/Spanker JSON representation | Last visible development was about two years old; rejected because Windows/Swift 6 and exact 2.7 behavior are unverified and it would replace `JSONValue` |
| freysie/SwiftPath | MIT | Historical Swift package; Apple focus; its own users report critical Linux failures; no Windows evidence | JSONPath-like, but not in the cross-implementation comparison because of correctness failures | Inactive/legacy; rejected |
| RBBJSON | MIT | SwiftPM, Apple and historical Linux support; no Windows or Swift 6 verification | Only JSONPath-inspired query syntax, not Jayway JSONPath | Last visible changes were roughly four years old; rejected |
| SwifterJSON | MIT | Current SwiftPM package; Apple support, with no demonstrated Windows JSONPath evaluator | Dynamic JSON wrapper and traversal API, not JSONPath | Maintained as a JSON wrapper but does not solve this task; rejected |

Thus no candidate demonstrates the required combination of license suitability,
Swift 6, Windows, macOS, iOS, SwiftPM, required JSONPath range, and Jayway 2.7
semantics. Adopting one would add a second JSON model and still require extensive
compatibility shims.

The selected implementation is a small pure-Swift evaluator over the existing
`JSONValue`. It has no Apple-only imports and supports the commonly used,
deterministic Jayway subset shown above. This keeps Windows support testable and
makes unsupported filters/functions explicit. `JSONValue` remains a general
Codable representation; JSONPath parsing and traversal live solely in the
selector adapter.

## JSON to `RuleValue`

The adapter exposes Android `getStringList` shape because `RuleExecutor` has a
single selector result API: a JSON array becomes its members as `.strings`; a
scalar or object becomes a one-item `.strings`; an empty/missing result becomes
`.none`. Strings are unchanged, integers use decimal spelling, doubles retain a
decimal representation, booleans are lowercase, null is `"null"`, and objects
or nested arrays use compact JSON. Order and duplicate array values are kept.

For `.strings`, Android passes the list object to `JsonPath.parse`; it does not
parse every member as JSON. Swift mirrors that by treating it as an array of
JSON strings. This is important when JSONPath follows another list-producing
stage.

## Known differences

- `JSONValue.object` uses a Swift dictionary and cannot preserve JSON member
  insertion order. Wildcard and recursive traversal therefore use deterministic
  sorted-key order. Named recursive descent evaluates a reached descendant
  object's matching property before that object's deeper descendants; the root
  object's own matching property remains in its sorted traversal position.
- Advanced Jayway filters, regex predicates, operators, functions, script
  expressions, and mutation APIs are unsupported.
- The public `RuleValue` cannot carry raw map/list nodes like Android
  `getElement/getElements`; conversion follows the string-list execution path.
- Compatible mode intentionally hides selector failures like Android's string
  extraction. Strict diagnostics are a READ3-IOS extension.
