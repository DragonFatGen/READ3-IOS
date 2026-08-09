# Historical JSoup and CSS selector execution

This document describes the platform-neutral selector adapter derived from
Android Legado commit `c043ea72fd2698d27a7dcbc0beb7844c572e544c` and the
SwiftSoup 2.13.7 implementation selected for READ3-IOS. Android analysis used a
detached checkout in the system temporary directory. `Reference/READ3.0` was
not modified.

## Android evidence

The primary implementation is
`app/src/main/java/io/legado/app/model/analyzeRule/AnalyzeByJSoup.kt`, read with
`AnalyzeRule.SourceRule`, `AnalyzeRule.getString/getStringList/getElement/
getElements`, and `RuleAnalyzer`.

`AnalyzeByJSoup.parse` accepts an existing JSoup element directly. Other values
are converted with `toString()` and parsed as HTML. Consequently a Kotlin list
is not processed as independent HTML documents; its bracketed `List.toString()`
representation is parsed once. `JSoupRuleSelectorExecutor` mirrors this boundary
for `RuleValue.strings` using `[item, item]` formatting.

Historical extraction starts with the parsed document element. Every `@` field
except the last selects nodes below every node from the preceding stage. The
last field extracts text, HTML, or an attribute. The intermediate selector
shortcuts are:

| Historical syntax | Android selection |
| --- | --- |
| empty or `children` | direct element children |
| `tag.name` | `getElementsByTag(name)` |
| `class.name` | `getElementsByClass(name)` |
| `id.name` | ID collector |
| `text.value` | elements containing value in own text |
| other text | JSoup CSS `select` |

`RuleAnalyzer` performs balanced `@` splitting, so `@` inside bracketed CSS
attribute selectors or quoted groups is not a child-chain separator.

`@@` is handled by `AnalyzeRule.SourceRule`, not JSoup: it removes two leading
characters and forces default/historical mode. READ3-IOS now makes that decision
before checking explicit prefixes, matching the Android `when` branch order.

## Explicit `@CSS:`

Android removes the case-insensitive prefix and uses JSoup CSS directly. For
string extraction, the final literal `@` separates the CSS query from the
result field. It does not run historical child selection or historical index
parsing. READ3-IOS represents this as `SelectorRule.type == .css` and follows
the same last-`@` boundary.

The Android string extractor assumes that final field exists and would fail on
an absent delimiter. The Swift adapter returns `selectorExecutionFailed`
instead of crashing. Element-only `@CSS:` selection cannot currently be exposed
because `RuleValue` intentionally contains strings rather than DOM nodes.

## Result extraction

The final historical field, or the field after the final explicit-CSS `@`, has
these meanings:

- `text`: normalized descendant text for each selected element. Empty strings
  are discarded.
- `ownText`: normalized direct text only. Empty strings are discarded.
- `textNodes`: trim each direct text node using Android's character `<= U+0020`
  rule, discard empty nodes, and join a single element's nodes with newline.
- `html`: remove descendant `script` and `style` nodes, then return the combined
  outer HTML of all selected elements as one list item. Despite its name this
  is not inner HTML.
- `all`: return combined outer HTML without removing `script` or `style`.
- any other field: call `attr(field)` for every element, discard blank values,
  and remove duplicates while preserving first occurrence order.

Android has no `outerHtml` extraction keyword in this revision; `all` is the
supported spelling. It also does not interpret `attr.href` specially: `href`,
`src`, `data-*`, and other attribute names are passed directly. The adapter does
not resolve relative URLs.

The generic executor preserves selector results as `.strings`, even for one
item. This corresponds to Android `getStringList`; callers needing Android
`getString` use `RuleValue.stringValue`, which joins list items with newline.
No match or only filtered empty values becomes `.none`.

## Historical indexes and exclusion

Index filtering belongs to intermediate historical selection stages. Bracket
syntax supports comma-separated indices and inclusive ranges:

- `[0]`, `[1]`, `[-1]`
- `[0:3]` (indices 0 through 3, inclusive)
- `[0,2,4]`
- `[:4:2]`
- `[-1:0]` (reverse order)
- `[!0,2]` (exclude indices)

Positive range bounds beyond the list clamp to the final element; overly
negative bounds clamp to zero. Standalone out-of-range indices are ignored.
Duplicates are removed while first rule order is retained. Exclusion removes
valid resolved indices and leaves all other nodes; excluding every node yields
no result.

The older suffix form is also supported. `tag.li.0:2:-1` selects the listed
indices, while `tag.li!1:3` excludes them. In Android this colon-separated old
form is a list of indices, not a Python-style slice.

Android has unusual behavior for negative range steps: it converts many of them
to a positive step using `step + elementCount`. The Swift index model preserves
that rule. This behavior should not be described as conventional Swift or Python
slicing.

## HTML parser choice

READ3-IOS uses SwiftSoup 2.13.7 through Swift Package Manager.

- Repository: `https://github.com/scinfu/SwiftSoup`
- License: MIT. The upstream license retains both jsoup and Swift-port notices
  and is compatible with the repository's distribution goals when its notice is
  preserved by SwiftPM/source distribution.
- Implementation: pure Swift with Foundation; no WebKit, UIKit, or Apple-only
  HTML parser.
- CSS capability: tag, ID, class, attribute selectors, descendant and direct
  child combinators, sibling combinators, groups, and a broad jsoup-style set of
  pseudo selectors.
- Declared platforms: Apple platforms and Linux in upstream documentation.
  Version 2.13.7 contains an explicit `os(Windows)` mutex implementation, but
  upstream CI only covers macOS and Ubuntu. Windows compatibility is therefore
  plausible from source, not considered verified until READ3-IOS Windows CI
  resolves, builds, and tests it.

## Compatibility assessment

Fully aligned for covered fixtures:

- historical `@` stage order;
- `@@` mode forcing;
- explicit `@CSS:` extraction boundary;
- tag/class/ID/CSS intermediate selection;
- bracket and legacy index filtering;
- text, ownText, textNodes, `html`, `all`, and direct attributes;
- empty filtering, attribute deduplication, and raw relative URLs.

Approximately compatible:

- SwiftSoup is a Swift port of jsoup but not the identical Java version bundled
  by the pinned Android commit. Advanced CSS pseudo selectors and malformed HTML
  recovery may produce different trees or serialization.
- Whitespace normalization and pretty-printed outer HTML can differ in obscure
  cases. Tests assert semantic content where formatting is parser-dependent.
- `.strings` input reproduces Kotlin's visible list formatting, but Swift strings
  cannot retain Android's actual `Element`, `Elements`, or `JXNode` object types
  between unrelated executor stages.

Not supported in this phase:

- returning DOM nodes from `getElement/getElements` as a public RuleValue;
- element-only explicit CSS rules without a final extraction field;
- JavaScript, HTTP, URL completion, or DOM persistence; JSONPath and XPath are
  separate adapters documented in `docs/rule-jsonpath.md` and
  `docs/rule-xpath.md`;
- guaranteed parity for every jsoup selector or malformed document.
