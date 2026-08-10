# Rule node context architecture

## Evidence and problem

This design is pinned to Android Legado commit
`c043ea72fd2698d27a7dcbc0beb7844c572e544c`. `BookList` calls
`AnalyzeRule.getElements(bookList)` and passes every returned object back to
`AnalyzeRule.setContent(item)`. Subsequent field calls therefore start from the same object,
not from serialized HTML or JSON.

- JSoup list items are `org.jsoup.nodes.Element` objects.
- JSONPath list items are Jayway provider values: maps, lists, strings, numbers, Booleans,
  or null.
- XPath list items are `org.seimicrawler.xpath.JXNode` objects. Element nodes retain a
  relative XPath context.
- `AnalyzeByJSoup`, `AnalyzeByJSonPath`, and `AnalyzeByXPath` all accept those objects
  directly. A JSoup element can also become an XPath root without reparsing the response.

The existing `RuleValue.none/string/strings` is intentionally a final scalar/list-of-scalar
result. Making a book-list item travel through it would lose node identity and force every
field to parse the complete response again.

## Options considered

| Design | Fidelity and cost | Type and compatibility consequences |
| --- | --- | --- |
| A. Add `.node/.nodes` to `RuleValue` | Direct, but every regex, template, variable, JavaScript, and combination switch gains structured-value behavior | Couples the stable public scalar result to selector implementation lifetimes and makes `Equatable`/`Sendable` semantics surprising |
| B. Add a node to `RuleExecutionInput` | Preserves the current item while keeping returned `RuleValue` scalar | Still needs a selector-owned node abstraction; by itself it does not define list selection or third-party type hiding |
| C. Introduce `RuleNode`/`RuleNodeCollection` for selector results | Keeps HTML/JSON/XPath values lossless and isolates conversion | Requires a small node-selection execution path beside scalar `RuleExecutor` |

### Chosen architecture

The implementation combines B and C. `RuleValue` remains unchanged.
`RuleExecutionInput` can carry either a scalar value or a `RuleNode`. `RuleNode` is a
platform-neutral opaque handle with a public kind; SwiftSoup and JSONPath implementation
types remain internal. `RuleNodeExecutor` evaluates book-list expressions into a
`RuleNodeCollection`, while the existing `RuleExecutor` evaluates field expressions from a
node-bearing input into `RuleValue`.

This keeps one parsed response graph per search. HTML handles from one response share a
locked owner, JSON nodes keep `JSONValue` directly, and XPath element nodes reuse the HTML
handle. Different responses have different owners, so concurrent searches do not share
mutable parser state. The lock is the documented `Sendable` boundary around SwiftSoup,
whose node classes do not declare `Sendable`; it does not make network or asynchronous work
synchronous.

## Relative execution and conversion

Selector executors receive `RuleExecutionInput`. When it contains a node, JSoup, JSONPath,
and XPath start at that node. A selector result is a normal `RuleValue`, so a following
regex, template, variable write, or pure JavaScript expression uses the selected string.
No field reparses the complete HTTP body.

Structured-to-string conversion is explicit:

- HTML and XPath element nodes use element outer HTML where Android calls `toString()`.
- JSON scalar nodes use their scalar representation.
- JSON objects and arrays use deterministic sorted-key compact JSON at an explicit string
  boundary. Android Java map/list `toString()` is not byte-identical; this is documented
  rather than delegated to `String(describing:)`.

Regex and templates therefore never receive an opaque native object. A raw structured node
is converted only when the expression explicitly crosses into scalar execution. Selector
then regex and selector inside a template retain existing behavior.

## Combinations

For book-list selection, `&&` concatenates node collections, `||` returns the first
non-empty collection, `%%` interleaves collections, and the historical `@` child chain
applies each JSoup selector to the nodes selected by the previous step. These mirror
`AnalyzeRule.getElements` collection behavior. Regex, replacements, templates, variable
reads/writes, and JavaScript are not accepted as node-producing book-list operations.

Scalar combinations continue to use the existing `RuleExecutor`; introducing nodes does
not change established `RuleValue` behavior.

## JavaScript compatibility

Android Rhino receives the actual Element or map/list in `result`. JavaScriptCore currently
has no safe DOM/map binding for `RuleNode`. This phase supports JavaScript after a selector
has produced a scalar. JavaScript whose direct input is a structured node is explicitly
unsupported; it is not silently supplied outer HTML or compact JSON. Full structured
JavaScript bindings remain a later phase.

## Lifecycle, memory, and concurrency

A collection owns the parsed response graph for as long as any item handle survives.
Items are immutable handles. Search fields execute sequentially per item, and every item
gets a new `RuleExecutionContext`. Different searches may execute concurrently because
their node owners, variables, capture groups, and current results are independent. There is
no static mutable node cache.

The main retained cost is one parsed HTML or JSON graph per active response, instead of
`book count × field count` reparses. XPath over HTML shares the same graph.
