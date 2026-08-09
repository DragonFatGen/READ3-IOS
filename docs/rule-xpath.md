# Legado XPath selector execution

This analysis is pinned to Android Legado commit
`c043ea72fd2698d27a7dcbc0beb7844c572e544c`. Android and library sources were
read from detached checkouts in the system temporary directory;
`Reference/READ3.0` was not modified.

## Android implementation evidence

`AnalyzeByXPath.kt` uses `org.seimicrawler.xpath.JXDocument` and `JXNode` from
`cn.wanghaomiao:JsoupXpath:2.5.1`. The library is Apache-2.0 and implements its
grammar with ANTLR 4.7.2 over a jsoup DOM. Its POM depends on jsoup 1.14.2; the
Legado app also declares jsoup 1.14.3, which is the effective application parser.

String input is passed to `JXDocument.create(String)`, which calls
`Jsoup.parse(html).children()`. A jsoup `Document`, `Element`, or `Elements` is
used directly. An element-valued `JXNode` remains a node context; every other
input is converted with `toString()` and reparsed as HTML. Consequently Android
parses a Kotlin list once using its bracketed list representation rather than
parsing every member as a separate document. It wraps a trailing `</td>` in
`<tr>`, and a trailing `</tr>` or `</tbody>` in `<table>` before parsing.

`getStringList` calls `JXNode.asString()` for every result. Element nodes become
outer HTML. Synthetic `text()` nodes become their normalized own text. Attribute
and extension-node results are strings. Integers/longs, doubles, booleans, and
dates use Java string conversion. `getString` joins the `JXNode.toString()`
values with newline. `getElements` preserves raw `JXNode` values for later
Android stages, a shape the current Swift `RuleValue` cannot expose.

JsoupXpath turns parser, evaluation, unknown-function, and type errors into
`XpathSyntaxErrorException`. `AnalyzeByXPath` does not catch this exception, so
Android has no empty-result compatibility fallback for invalid XPath. Valid
queries with no nodes return an empty list. READ3-IOS therefore returns `.none`
for no match and a typed error for invalid/unsupported expressions in both
policies; strict mode provides more precise diagnostics where possible.

`AnalyzeRule.SourceRule` recognizes case-insensitive `@XPath:` and any leading
`/`. A relative XPath requires the explicit prefix. `RuleAnalyzer` protects
brackets and parentheses while splitting `&&`, `||`, and `%%`. `##`, templates,
variables, and source-rule sequencing are handled outside `AnalyzeByXPath`, as
they are by the Swift Parser and RuleExecutor.

## Compatibility matrix

| Syntax / behavior | Android 2.5.1 | Android result | Swift plan | Compatibility |
| --- | --- | --- | --- | --- |
| `.` | Yes | current element set | current roots | Near |
| `..` | Yes | unique parent elements (hash-set order) | unique parents in encounter order | Near |
| `/` child path | Yes | child element set | direct-child traversal | Yes for covered paths |
| `//` | Yes | jsoup descendant selection | descendant traversal in document order | Near |
| relative path | Yes with `@XPath:` | relative to document roots/current node | supported | Yes |
| element / `*` | Yes | element nodes | outer HTML strings | String-list calls: yes |
| `text()` | Yes, library-specific text blocks | direct or recursive normalized text blocks | SwiftSoup text nodes, normalized | Near |
| `node()` | Yes, children then nonblank own text | elements plus synthetic text element | children plus own text strings | Near |
| `@name`, `attribute::name` | Yes | raw attribute strings | raw strings, no URL resolution | Yes |
| `[1]` | Yes | first among same-tag siblings | same-tag positional filtering | Yes |
| `[last()]` | Yes (`last()` returns `-1`) | last among same-tag siblings | last among same-tag siblings | Yes |
| `[position()=1]` | Yes | same-tag position | supported | Yes |
| `[@class='x']`, `[@class]` | Yes | matching elements | supported | Yes |
| `[text()='x']` | Yes | direct text-list string comparison | supported common case | Near |
| `contains()` | Yes | boolean/predicate | supported | Yes |
| `starts-with()` | Yes | boolean/predicate | supported | Yes |
| `count(path)` | Yes | one numeric node, commonly Double spelling such as `2.0` | supported with Android spelling | Near |
| top-level boolean | Yes | one lowercase boolean node | supported for contains/starts-with | Yes |
| `string(...)` | Grammar accepts, function is not registered | throws wrapped syntax error | unsupported typed error | Yes |
| `normalize-space(...)` | Grammar accepts, function is not registered | throws wrapped syntax error | unsupported typed error | Yes |
| `allText()`, `html()`, `outerHtml()` | JsoupXpath extensions | string list | supported | Near |
| axes beyond child/descendant/attribute/parent/self | Library supports many | node set | deferred | No |
| union, arithmetic, regex/extended operators | Library supports broad custom grammar | mixed | deferred | No |

## Dependency decision

| Option | License / packaging | Cross-platform and parser assessment | Decision |
| --- | --- | --- | --- |
| libxml2 wrapper | MIT; normally a SwiftPM system-library or binary wrapper | Mature XPath 1.0 and XML/HTML4 support, but no uniform preinstalled Windows SDK/library, adds C ABI and binary-distribution work, and HTML recovery differs from jsoup | Rejected for this phase |
| SwiftXMLTools / similar pure-Swift XML packages | Package-specific permissive licenses and SwiftPM | XPath-like APIs focus on well-formed XML; Windows and Swift 6 CI are not demonstrated consistently; HTML tag-soup behavior does not match jsoup | Rejected |
| Foundation `XMLDocument` / `NSXMLDocument` | Platform framework | Apple-only and unsuitable for Windows; HTML tolerance differs | Prohibited/rejected |
| SwiftSoup DOM plus XPath-to-DOM evaluator | Existing MIT SwiftPM dependency; pure Swift; current package already exercises its Windows-specific source paths | Reuses the closest available jsoup port and existing HTML recovery; XPath must be a documented subset | Selected |
| Independent HTML/XML DOM and XPath implementation | No dependency | Would duplicate parsing and diverge more from Android | Rejected |

No dependency is added. The implementation uses the existing SwiftSoup 2.13.7
DOM and a stateless parser/evaluator for the Android-common subset. This keeps
Swift 6, Windows, macOS, iOS, and SwiftPM risk bounded. SwiftSoup remains a port,
not the exact Java jsoup version, so malformed HTML recovery and serialization
are approximately compatible.

## XPath to `RuleValue`

The generic selector boundary models Android `getStringList`:

- element node set -> `.strings` of outer HTML;
- `text()`, attribute, `allText()`, `html()`, `outerHtml()` -> `.strings`;
- scalar string -> one `.strings` member;
- number -> one decimal member (`count` uses a `.0` suffix like JsoupXpath's
  Double conversion);
- boolean -> one lowercase `true`/`false` member;
- valid empty node set -> `.none`;
- invalid document/path or unsupported function -> typed execution error.

Empty strings returned by valid attribute/text operations remain list members.
Relative URLs are never resolved in the XPath layer.

## Known differences and deferred syntax

- Swift cannot retain Android `JXNode`/jsoup `Element` values in `RuleValue`, so
  node-to-node execution across selector stages is serialized as strings.
- SwiftSoup 2.13.7 may build or serialize malformed HTML differently from Java
  jsoup 1.14.3.
- Parent deduplication preserves encounter order; Android uses a `HashSet`.
- Full XPath 1.0, namespaces, union, arbitrary axes, arithmetic, variables,
  JsoupXpath regex operators, date and substring extensions are deferred.
- `string()` and `normalize-space()` are intentionally not implemented because
  the pinned Android library does not register them.
