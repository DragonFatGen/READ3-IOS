import SwiftSoup

/// Advisory only; never changes selectors, request policy or success/failure.
enum SearchPageHint {
    static func classify(_ body: String) -> SearchDiagnostic.PageHint {
        // Do not add unbounded diagnostic parsing or classify a truncated page.
        guard body.utf8.count <= 262_144 else { return .unknown }
        do {
            let document = try SwiftSoup.parse(body)
            var hints: [SearchDiagnostic.PageHint] = []
            let searchForms = try document.select("form[role=search], form:has(input[type=search])")
            if !searchForms.array().isEmpty { hints.append(.searchForm) }
            // Require both structural and metadata evidence, not a URL substring.
            if !(try document.select("meta[property='og:type'][content=book]")).array().isEmpty,
               !(try document.select("meta[property='og:title'][content]")).array().isEmpty,
               !(try document.select("h1")).array().isEmpty {
                hints.append(.bookDetail)
            }
            let loginForms = try document.select(
                "form:has(input[type=password]):has(input[name=username]), "
                + "form:has(input[type=password]):has(input[type=email])"
            )
            if !loginForms.array().isEmpty { hints.append(.loginOrVerification) }
            // Conflicting evidence (e.g. a shared login/search widget) is ambiguous.
            return hints.count == 1 ? hints[0] : .unknown
        } catch { return .unknown }
    }
}
