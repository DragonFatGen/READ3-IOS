import Foundation

/// Safe observations, separate from results and errors. Nil counts are not zero.
public struct SearchDiagnostic: Codable, Sendable, Equatable {
    public enum Stage: String, Codable, Sendable {
        case definition, requestBuild, request, responseDecode, bookList, fields, parsed, resultSelection
    }
    public enum RuleFailure: String, Codable, Sendable {
        case ruleParser, selector, javascript, unsupportedCapability, unknown
    }
    public enum Field: String, Codable, Sendable {
        case name, author, kind, wordCount, lastChapter, intro, coverUrl, bookUrl
    }
    public enum ContentType: String, Codable, Sendable {
        case html, json, text, xml, other, unknown
    }
    public enum PageHint: String, Codable, Sendable {
        case searchForm, bookDetail, loginOrVerification, other, unknown
    }

    public internal(set) var lastStage: Stage = .definition
    public internal(set) var bookListMatchedCount: Int?
    public internal(set) var missingNameCount: Int?
    public internal(set) var missingBookURLCount: Int?
    public internal(set) var filteredItemCount: Int?
    public internal(set) var finalResultCount: Int?
    public internal(set) var ruleThrew: Bool?
    public internal(set) var ruleFailureCategory: RuleFailure?
    public internal(set) var lastField: Field?
    public internal(set) var requestedBookIndex: Int?
    public internal(set) var indexInRange: Bool?
    public internal(set) var responseStatusCode: Int?
    public internal(set) var responseContentType: ContentType?
    public internal(set) var responseByteCount: Int?
    public internal(set) var responseRedirected: Bool?
    public internal(set) var pageHint: PageHint = .unknown

    public init() {}

    mutating func recordRuleError(_ error: any Error) {
        ruleThrew = true
        // Keep the first observed rule error, including optional-field errors
        // that the existing parser deliberately tolerates. Never inspect messages.
        guard ruleFailureCategory == nil else { return }
        switch error {
        case is RuleSyntaxError: ruleFailureCategory = .ruleParser
        case is JavaScriptExecutionError: ruleFailureCategory = .javascript
        case let value as RuleExecutionError:
            switch value {
            case .invalidRegularExpression, .invalidCaptureGroup: ruleFailureCategory = .ruleParser
            case .unsupportedExecutionNode, .unsupportedJSONPathFeature, .unsupportedXPathFeature:
                ruleFailureCategory = .unsupportedCapability
            default: ruleFailureCategory = .selector
            }
        case let value as BookListParseError:
            switch value {
            case .unsupportedJavaScriptNetworkHost: ruleFailureCategory = .unsupportedCapability
            default: ruleFailureCategory = .unknown
            }
        default: ruleFailureCategory = .unknown
        }
    }

    mutating func recordResponse(_ response: HTTPResponse) {
        responseStatusCode = (100...599).contains(response.statusCode) ? response.statusCode : nil
        responseByteCount = response.data.count
        responseRedirected = !response.redirects.isEmpty
        let mime = response.headers["Content-Type"]?.split(separator: ";", maxSplits: 1)
            .first?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        switch mime {
        case "text/html", "application/xhtml+xml": responseContentType = .html
        case "application/json", "text/json": responseContentType = .json
        case "text/plain": responseContentType = .text
        case "application/xml", "text/xml": responseContentType = .xml
        case nil, "": responseContentType = .unknown
        default: responseContentType = .other
        }
    }

    // Explicit nulls distinguish stages that did not run from measured zeroes.
    public func encode(to encoder: any Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(lastStage, forKey: .lastStage)
        try values.encode(bookListMatchedCount, forKey: .bookListMatchedCount)
        try values.encode(missingNameCount, forKey: .missingNameCount)
        try values.encode(missingBookURLCount, forKey: .missingBookURLCount)
        try values.encode(filteredItemCount, forKey: .filteredItemCount)
        try values.encode(finalResultCount, forKey: .finalResultCount)
        try values.encode(ruleThrew, forKey: .ruleThrew)
        try values.encode(ruleFailureCategory, forKey: .ruleFailureCategory)
        try values.encode(lastField, forKey: .lastField)
        try values.encode(requestedBookIndex, forKey: .requestedBookIndex)
        try values.encode(indexInRange, forKey: .indexInRange)
        try values.encode(responseStatusCode, forKey: .responseStatusCode)
        try values.encode(responseContentType, forKey: .responseContentType)
        try values.encode(responseByteCount, forKey: .responseByteCount)
        try values.encode(responseRedirected, forKey: .responseRedirected)
        try values.encode(pageHint, forKey: .pageHint)
    }
}
