# Deterministic compatibility runner

`BookSourceCompatibilityRunner` composes the existing importer, search,
book-info, TOC, and content runtimes without adding networking or rule behavior
of its own. A caller injects one `HTTPClient`; tests use `MockHTTPClient` with
fixture responses, so the runner never requires live websites.

The runner accepts raw BookSource JSON, imports it through `BookSourceImporter`,
selects one search result and one chapter by explicit zero-based indexes, and
returns `CompatibilityReport` with every available intermediate result. Reports
do not throw for compatibility failures. `CompatibilityFailure` records a
specific category (`import`, `request`, `charset`, `ruleParser`, `selector`,
`javascript`, or `unsupportedCapability`) and the active business operation
(`search`, `bookInfo`, `toc`, or `content`). Empty results remain business-stage
failures. Diagnostic text is length-limited and redacts common credentials.

The desensitized Chinese fixture covers import/unknown-field preservation, a
GBK-encoded search request, and four GBK response bodies across Import -> Search
-> BookInfo -> TOC -> Content. It is intentionally local and deterministic.
Pagination, JavaScript network bridges, WebView login, statistical charset
detection, and live-site validation are outside this runner. Production
`java.ajax/get/post/head` remains an explicit unsupported capability.
