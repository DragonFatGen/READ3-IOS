import Foundation

public struct LegacySourceNormalizer: Sendable {
    public init() {}

    func normalize(_ input: JSONValue) throws -> NormalizationOutput {
        guard case let .object(inputFields) = input else {
            throw SourceImportError.topLevelMustBeObject
        }
        var state = NormalizationState(fields: inputFields)
        try state.run()
        return NormalizationOutput(
            value: .object(state.fields),
            warnings: state.warnings,
            migrations: state.migrations
        )
    }
}

struct NormalizationOutput {
    let value: JSONValue
    let warnings: [SourceImportWarning]
    let migrations: [SourceMigration]
}

private struct NormalizationState {
    var fields: [String: JSONValue]
    var warnings: [SourceImportWarning] = []
    var migrations: [SourceMigration] = []

    private static let ruleGroups: [(String, [(String, String)])] = [
        ("ruleSearch", [
            ("ruleSearchList", "bookList"), ("ruleSearchName", "name"),
            ("ruleSearchAuthor", "author"), ("ruleSearchIntroduce", "intro"),
            ("ruleSearchKind", "kind"), ("ruleSearchNoteUrl", "bookUrl"),
            ("ruleSearchCoverUrl", "coverUrl"),
            ("ruleSearchLastChapter", "lastChapter")
        ]),
        ("ruleExplore", [
            ("ruleFindList", "bookList"), ("ruleFindName", "name"),
            ("ruleFindAuthor", "author"), ("ruleFindIntroduce", "intro"),
            ("ruleFindKind", "kind"), ("ruleFindNoteUrl", "bookUrl"),
            ("ruleFindCoverUrl", "coverUrl"),
            ("ruleFindLastChapter", "lastChapter")
        ]),
        ("ruleBookInfo", [
            ("ruleBookInfoInit", "init"), ("ruleBookName", "name"),
            ("ruleBookAuthor", "author"), ("ruleIntroduce", "intro"),
            ("ruleBookKind", "kind"), ("ruleCoverUrl", "coverUrl"),
            ("ruleBookLastChapter", "lastChapter"), ("ruleChapterUrl", "tocUrl")
        ]),
        ("ruleToc", [
            ("ruleChapterList", "chapterList"), ("ruleChapterName", "chapterName"),
            ("ruleContentUrl", "chapterUrl"), ("ruleChapterUrlNext", "nextTocUrl")
        ]),
        ("ruleContent", [
            ("ruleBookContent", "content"),
            ("ruleBookContentReplace", "replaceRegex"),
            ("ruleContentUrlNext", "nextContentUrl")
        ])
    ]

    mutating func run() throws {
        let legacyKeys = Set(Self.ruleGroups.flatMap { $0.1.map(\.0) })
            .union(["ruleBookUrlPattern", "serialNumber", "enable", "httpUserAgent",
                    "ruleSearchUrl", "ruleFindUrl"])
        let hadLegacyInput = fields.keys.contains(where: legacyKeys.contains)
            || fields["bookSourceType"] == .string("AUDIO")

        try normalizeRuleObjects()
        for group in Self.ruleGroups {
            migrateRuleGroup(target: group.0, mappings: group.1)
        }
        migrateStringField(old: "ruleBookUrlPattern", new: "bookUrlPattern") { $0 }
        try migrateLegacyInteger(old: "serialNumber", new: "customOrder", int32: true)
        migrateBooleanField(old: "enable", new: "enabled")
        try migrateUserAgent()
        try migrateURLField(old: "ruleSearchUrl", new: "searchUrl", multiple: false)
        try migrateURLField(old: "ruleFindUrl", new: "exploreUrl", multiple: true)
        try normalizeSourceType()
        try normalizeLoginURL()
        try normalizeJSONBackedString(field: "loginUi")
        try normalizeNumericFields()

        if hadLegacyInput {
            if fields["bookSourceComment"] == nil || fields["bookSourceComment"] == .null {
                fields["bookSourceComment"] = .string("")
            }
            if fields["enabledExplore"] == nil, isBlank(fields["exploreUrl"]) {
                fields["enabledExplore"] = .bool(false)
                migrations.append(.init(
                    kind: .emptyExploreURL,
                    sourceFields: ["exploreUrl"],
                    destinationField: "enabledExplore",
                    message: "Disabled exploration because the legacy discovery URL is empty."
                ))
            }
        }
    }

    mutating func normalizeRuleObjects() throws {
        for field in Self.ruleGroups.map(\.0) {
            guard let value = fields[field] else { continue }
            switch value {
            case .null, .object:
                continue
            case let .string(json):
                guard let data = json.data(using: .utf8),
                      let decoded = try? JSONDecoder().decode(JSONValue.self, from: data),
                      case .object = decoded else {
                    throw SourceImportError.invalidRuleJSONString(field: field)
                }
                fields[field] = decoded
                migrations.append(.init(
                    kind: .stringRuleObject,
                    sourceFields: [field],
                    destinationField: field,
                    message: "Decoded a JSON-string rule object."
                ))
            default:
                throw SourceImportError.invalidField(field: field, expected: "an object or JSON object string")
            }
        }
    }

    mutating func migrateRuleGroup(target: String, mappings: [(String, String)]) {
        let oldFields = mappings.map(\.0).filter { fields[$0] != nil }
        guard !oldFields.isEmpty else { return }
        let modernExists = fields[target] != nil
        if modernExists {
            warnings.append(.init(
                code: .modernFieldWonConflict,
                field: target,
                message: "The modern \(target) value took precedence over legacy root fields."
            ))
        }
        var migrated: [String: JSONValue] = [:]
        var safelyHandled: [String] = []

        for (old, new) in mappings {
            guard let value = fields[old] else { continue }
            switch value {
            case .null:
                safelyHandled.append(old)
            case let .string(rule):
                safelyHandled.append(old)
                if !modernExists, let converted = Self.toNewRule(rule) {
                    if target == "ruleContent", new == "content",
                       converted.hasPrefix("$"), !converted.hasPrefix("$.") {
                        migrated[new] = .string(String(converted.dropFirst()))
                    } else {
                        migrated[new] = .string(converted)
                    }
                }
            default:
                warnings.append(.init(
                    code: .unsupportedLegacyValuePreserved,
                    field: old,
                    message: "The legacy rule is not a string and remains at the root."
                ))
            }
        }

        for key in safelyHandled { fields.removeValue(forKey: key) }
        guard !safelyHandled.isEmpty else { return }
        if modernExists {
            migrations.append(.init(
                kind: .discardedLegacyConflict,
                sourceFields: safelyHandled,
                destinationField: target,
                message: "Removed safely interpreted duplicate legacy fields without overwriting the modern value."
            ))
        } else {
            if target == "ruleContent", migrated["content"] == nil {
                migrated["content"] = .string("")
            }
            fields[target] = .object(migrated)
            migrations.append(.init(
                kind: .legacyRuleGroup,
                sourceFields: safelyHandled,
                destinationField: target,
                message: "Moved legacy root rules into \(target)."
            ))
        }
    }

    mutating func migrateStringField(
        old: String,
        new: String,
        transform: (String) -> String?
    ) {
        guard let value = fields[old] else { return }
        guard case let .string(string) = value, let converted = transform(string) else {
            if value == .null { fields.removeValue(forKey: old) }
            else { preserveWarning(field: old, expected: "a string") }
            return
        }
        resolveLegacyValue(old: old, new: new, value: .string(converted))
    }

    mutating func migrateBooleanField(old: String, new: String) {
        guard let value = fields[old] else { return }
        guard case .bool = value else {
            if value == .null { fields.removeValue(forKey: old) }
            else { preserveWarning(field: old, expected: "a Boolean") }
            return
        }
        resolveLegacyValue(old: old, new: new, value: value)
    }

    mutating func migrateLegacyInteger(old: String, new: String, int32: Bool) throws {
        guard let value = fields[old] else { return }
        guard let integer = integerValue(value, int32: int32) else {
            if value == .null { fields.removeValue(forKey: old) }
            else { preserveWarning(field: old, expected: "an in-range number") }
            return
        }
        resolveLegacyValue(old: old, new: new, value: .integer(integer))
    }

    mutating func migrateUserAgent() throws {
        guard let value = fields["httpUserAgent"] else { return }
        guard case let .string(userAgent) = value else {
            if value == .null { fields.removeValue(forKey: "httpUserAgent") }
            else { preserveWarning(field: "httpUserAgent", expected: "a string") }
            return
        }
        let header = try jsonString(.object(["User-Agent": .string(userAgent)]))
        resolveLegacyValue(old: "httpUserAgent", new: "header", value: .string(header))
    }

    mutating func migrateURLField(old: String, new: String, multiple: Bool) throws {
        guard let value = fields[old] else { return }
        guard case let .string(string) = value else {
            if value == .null { fields.removeValue(forKey: old) }
            else { preserveWarning(field: old, expected: "a string") }
            return
        }
        if !multiple {
            let pipeParts = string.components(separatedBy: "|")
            if pipeParts.count > 2 || (pipeParts.count == 2 && !pipeParts[1].contains("=")) {
                preserveWarning(field: old, expected: "a safely convertible legacy URL")
                return
            }
        }
        let converted = multiple ? try Self.toNewURLs(string) : try Self.toNewURL(string)
        if let converted {
            resolveLegacyValue(old: old, new: new, value: .string(converted))
        } else {
            fields.removeValue(forKey: old)
        }
    }

    mutating func resolveLegacyValue(old: String, new: String, value: JSONValue) {
        fields.removeValue(forKey: old)
        if fields[new] != nil {
            warnings.append(.init(
                code: .modernFieldWonConflict,
                field: new,
                message: "The modern \(new) value took precedence over \(old)."
            ))
            migrations.append(.init(
                kind: .discardedLegacyConflict,
                sourceFields: [old],
                destinationField: new,
                message: "Removed the duplicate legacy field without overwriting the modern value."
            ))
        } else {
            fields[new] = value
            migrations.append(.init(
                kind: .legacyField,
                sourceFields: [old],
                destinationField: new,
                message: "Renamed and normalized a legacy field."
            ))
        }
    }

    mutating func normalizeSourceType() throws {
        guard let value = fields["bookSourceType"] else { return }
        if case let .string(typeName) = value {
            let normalizedType: Int64 = typeName == "AUDIO" ? 1 : 0
            if typeName != "AUDIO" {
                var preservationField = "legacyBookSourceType"
                var suffix = 2
                while fields[preservationField] != nil {
                    preservationField = "legacyBookSourceType\(suffix)"
                    suffix += 1
                }
                fields[preservationField] = value
                warnings.append(.init(
                    code: .unsupportedLegacyValuePreserved,
                    field: "bookSourceType",
                    message: "Unknown legacy source type was preserved in \(preservationField) and mapped to Android's text default."
                ))
            }
            fields["bookSourceType"] = .integer(normalizedType)
            migrations.append(.init(
                kind: .legacySourceType,
                sourceFields: ["bookSourceType"],
                destinationField: "bookSourceType",
                message: "Converted a legacy source type name to its numeric representation."
            ))
            return
        }
        try normalizeIntegerField("bookSourceType", int32: true)
    }

    mutating func normalizeLoginURL() throws {
        guard let value = fields["loginUrl"] else { return }
        switch value {
        case .null, .string:
            return
        case let .object(object):
            guard case let .string(url)? = object["url"] else {
                throw SourceImportError.invalidField(field: "loginUrl.url", expected: "a string")
            }
            if object.count > 1 {
                var preservationField = "legacyLoginUrl"
                var suffix = 2
                while fields[preservationField] != nil {
                    preservationField = "legacyLoginUrl\(suffix)"
                    suffix += 1
                }
                fields[preservationField] = value
                warnings.append(.init(
                    code: .unsupportedLegacyValuePreserved,
                    field: "loginUrl",
                    message: "Extra loginUrl object members were preserved in \(preservationField)."
                ))
            }
            fields["loginUrl"] = .string(url)
            migrations.append(.init(
                kind: .loginURLRepresentation,
                sourceFields: ["loginUrl"],
                destinationField: "loginUrl",
                message: "Extracted url from the object form of loginUrl."
            ))
        case .array:
            fields["loginUrl"] = .string(try jsonString(value))
            warnings.append(.init(
                code: .androidBehaviorDifference,
                field: "loginUrl",
                message: "Array loginUrl was preserved as a JSON string; Android's object-only lookup can fail for this form."
            ))
            migrations.append(.init(
                kind: .loginURLRepresentation,
                sourceFields: ["loginUrl"],
                destinationField: "loginUrl",
                message: "Serialized array loginUrl without discarding its entries."
            ))
        default:
            throw SourceImportError.invalidField(field: "loginUrl", expected: "a string, object, or array")
        }
    }

    mutating func normalizeJSONBackedString(field: String) throws {
        guard let value = fields[field] else { return }
        switch value {
        case .null, .string:
            return
        case .object, .array:
            fields[field] = .string(try jsonString(value))
        default:
            throw SourceImportError.invalidField(field: field, expected: "a string, object, or array")
        }
    }

    mutating func normalizeNumericFields() throws {
        for field in ["customOrder", "weight"] { try normalizeIntegerField(field, int32: true) }
        for field in ["lastUpdateTime", "respondTime"] { try normalizeIntegerField(field, int32: false) }
    }

    mutating func normalizeIntegerField(_ field: String, int32: Bool) throws {
        guard let value = fields[field] else { return }
        if case .null = value { return }
        guard let integer = integerValue(value, int32: int32) else {
            throw SourceImportError.invalidField(
                field: field,
                expected: int32 ? "a 32-bit integer-compatible number" : "a 64-bit integer-compatible number"
            )
        }
        let normalized = JSONValue.integer(integer)
        if value != normalized {
            fields[field] = normalized
            warnings.append(.init(
                code: .numericValueCoerced,
                field: field,
                message: "Converted a numeric value to an integer."
            ))
            migrations.append(.init(
                kind: .numericCoercion,
                sourceFields: [field],
                destinationField: field,
                message: "Coerced the numeric representation to an integer."
            ))
        }
    }

    func integerValue(_ value: JSONValue, int32: Bool) -> Int64? {
        let candidate: Int64?
        switch value {
        case let .integer(integer):
            candidate = integer
        case let .number(number):
            guard number.isFinite,
                  number >= Double(Int64.min), number < Double(Int64.max) else { return nil }
            candidate = Int64(number.rounded(.towardZero))
        case let .string(string):
            candidate = Int64(string.trimmingCharacters(in: .whitespacesAndNewlines))
        default:
            return nil
        }
        guard let candidate else { return nil }
        if int32, candidate < Int64(Int32.min) || candidate > Int64(Int32.max) { return nil }
        return candidate
    }

    mutating func preserveWarning(field: String, expected: String) {
        warnings.append(.init(
            code: .unsupportedLegacyValuePreserved,
            field: field,
            message: "Expected \(expected); the legacy field remains unchanged."
        ))
    }

    func jsonString(_ value: JSONValue) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(value)
        guard let string = String(data: data, encoding: .utf8) else {
            throw SourceImportError.normalizedJSONEncodingFailed
        }
        return string
    }

    func isBlank(_ value: JSONValue?) -> Bool {
        guard case let .string(string)? = value else { return value == nil || value == .null }
        return string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    static func toNewRule(_ oldRule: String) -> String? {
        if oldRule.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return nil }
        var newRule = oldRule
        var reverse = false
        var allInOne = false
        if oldRule.hasPrefix("-") {
            reverse = true
            newRule = String(oldRule.dropFirst())
        }
        if newRule.hasPrefix("+") {
            allInOne = true
            newRule = String(newRule.dropFirst())
        }
        let lower = newRule.lowercased()
        if !lower.hasPrefix("@css:") && !lower.hasPrefix("@xpath:")
            && !newRule.hasPrefix("//") && !newRule.hasPrefix("##")
            && !newRule.hasPrefix(":") && !lower.contains("@js:")
            && !lower.contains("<js>") {
            if newRule.contains("#") && !newRule.contains("##") {
                newRule = oldRule.replacingOccurrences(of: "#", with: "##")
            }
            if newRule.contains("|") && !newRule.contains("||") {
                if newRule.contains("##") {
                    var parts = newRule.components(separatedBy: "##")
                    if parts[0].contains("|") {
                        parts[0] = parts[0].replacingOccurrences(of: "|", with: "||")
                        newRule = parts.joined(separator: "##")
                    }
                } else {
                    newRule = newRule.replacingOccurrences(of: "|", with: "||")
                }
            }
            if newRule.contains("&") && !newRule.contains("&&")
                && !newRule.contains("http") && !newRule.hasPrefix("/") {
                newRule = newRule.replacingOccurrences(of: "&", with: "&&")
            }
        }
        if allInOne { newRule = "+" + newRule }
        if reverse { newRule = "-" + newRule }
        return newRule
    }

    static func toNewURLs(_ oldURLs: String) throws -> String? {
        if oldURLs.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return nil }
        if oldURLs.hasPrefix("@js:") || oldURLs.hasPrefix("<js>") { return oldURLs }
        if !oldURLs.contains("\n") && !oldURLs.contains("&&") { return try toNewURL(oldURLs) }
        let pattern = try NSRegularExpression(pattern: "(&&|\\r?\\n)+")
        let range = NSRange(oldURLs.startIndex..., in: oldURLs)
        let split = pattern.stringByReplacingMatches(in: oldURLs, range: range, withTemplate: "\u{0}")
        return try split.split(separator: "\u{0}", omittingEmptySubsequences: false)
            .compactMap { try toNewURL(String($0)) }
            .map { $0.replacingOccurrences(of: "\\n\\s*", with: "", options: .regularExpression) }
            .joined(separator: "\n")
    }

    static func toNewURL(_ oldURL: String) throws -> String? {
        if oldURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return nil }
        var url = oldURL
        if url.lowercased().hasPrefix("<js>") {
            return url.replacingOccurrences(of: "=searchKey", with: "={{key}}")
                .replacingOccurrences(of: "=searchPage", with: "={{page}}")
        }
        var options: [String: JSONValue] = [:]
        if let range = url.range(of: "@Header:\\{.+?\\}", options: [.regularExpression, .caseInsensitive]) {
            let header = String(url[range])
            url.removeSubrange(range)
            options["headers"] = .string(String(header.dropFirst(8)))
        }
        var pipeParts = url.components(separatedBy: "|")
        url = pipeParts.removeFirst()
        if let charsetPart = pipeParts.first,
           let equals = charsetPart.firstIndex(of: "=") {
            options["charset"] = .string(String(charsetPart[charsetPart.index(after: equals)...]))
        }
        let pattern = try NSRegularExpression(pattern: "\\{\\{.+?\\}\\}", options: .caseInsensitive)
        var scripts: [String] = []
        while let match = pattern.firstMatch(in: url, range: NSRange(url.startIndex..., in: url)) {
            guard let range = Range(match.range, in: url) else { continue }
            scripts.append(String(url[range]))
            url.replaceSubrange(range, with: "$\(scripts.count - 1)")
        }
        url = url.replacingOccurrences(of: "{", with: "<")
            .replacingOccurrences(of: "}", with: ">")
            .replacingOccurrences(of: "searchKey", with: "{{key}}")
            .replacingOccurrences(of: "<searchPage([-+]1)>", with: "{{page$1}}", options: .regularExpression)
            .replacingOccurrences(of: "searchPage([-+]1)", with: "{{page$1}}", options: .regularExpression)
            .replacingOccurrences(of: "searchPage", with: "{{page}}")
        for (index, script) in scripts.enumerated() {
            let restored = script.replacingOccurrences(of: "searchKey", with: "key")
                .replacingOccurrences(of: "searchPage", with: "page")
            url = url.replacingOccurrences(of: "$\(index)", with: restored)
        }
        let atParts = url.components(separatedBy: "@")
        url = atParts[0]
        if atParts.count > 1 {
            options["method"] = .string("POST")
            options["body"] = .string(atParts[1])
        }
        if !options.isEmpty {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
            let data = try encoder.encode(JSONValue.object(options))
            guard let json = String(data: data, encoding: .utf8) else {
                throw SourceImportError.normalizedJSONEncodingFailed
            }
            url += "," + json
        }
        return url
    }
}
