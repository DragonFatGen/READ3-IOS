import Foundation

struct AndroidContentFormatter: Sendable {
    private let urlResolver = URLResolver()

    func format(_ html: String, redirectURL: String) -> String {
        var value = html
        value = replacing(#"(&nbsp;)+"#, in: value, with: " ")
        value = replacing(#"(&ensp;|&emsp;)"#, in: value, with: " ")
        value = replacing(#"(&thinsp;|&zwnj;|&zwj;)"#, in: value, with: "")
        value = replacing(
            #"</?(?:div|p|br|hr|h\d|article|dd|dl)[^>]*>"#,
            in: value,
            with: "\n"
        )
        value = replacing(#"<!--[^>]*-->"#, in: value, with: "")
        value = canonicalizeImages(in: value, redirectURL: redirectURL)
        value = replacing(#"</?(?!img)[a-zA-Z]+(?=[ >])[^<>]*>"#, in: value, with: "")
        value = replacing(#"\s*\n+\s*"#, in: value, with: "\n　　")
        value = replacing(#"^[\n\s]+"#, in: value, with: "　　")
        return replacing(#"[\n\s]+$"#, in: value, with: "")
    }

    private func canonicalizeImages(in value: String, redirectURL: String) -> String {
        let pattern = #"<img[^>]*src *= *"([^"{]*\{(?:[^{}]|\{[^}]+\})+\})"[^>]*>|<img[^>]*data-[^=]*= *"([^"]*)"[^>]*>|<img[^>]*src *= *"([^"]*)"[^>]*>"#
        guard let regex = try? NSRegularExpression(
            pattern: pattern,
            options: [.caseInsensitive]
        ) else { return value }
        var result = ""
        var cursor = value.startIndex
        let matches = regex.matches(
            in: value,
            range: NSRange(value.startIndex..<value.endIndex, in: value)
        )
        for match in matches {
            guard let range = Range(match.range, in: value) else { continue }
            result += value[cursor..<range.lowerBound]
            var rawURL = ""
            var options = ""
            if let sourceRange = Range(match.range(at: 1), in: value) {
                rawURL = String(value[sourceRange])
                let parts = splitOptions(rawURL)
                rawURL = parts.url
                options = parts.options.map { ",\($0)" } ?? ""
            } else if let dataRange = Range(match.range(at: 2), in: value) {
                rawURL = String(value[dataRange])
            } else if let sourceRange = Range(match.range(at: 3), in: value) {
                rawURL = String(value[sourceRange])
            }
            result += #"<img src=""# + urlResolver.resolve(rawURL, against: redirectURL) + options + #"">"#
            cursor = range.upperBound
        }
        result += value[cursor...]
        return result
    }

    private func splitOptions(_ value: String) -> (url: String, options: String?) {
        guard let regex = try? NSRegularExpression(pattern: #"\s*,\s*(?=\{)"#),
              let match = regex.firstMatch(
                in: value,
                range: NSRange(value.startIndex..<value.endIndex, in: value)
              ),
              let range = Range(match.range, in: value) else {
            return (value, nil)
        }
        return (String(value[..<range.lowerBound]), String(value[range.upperBound...]))
    }

    private func replacing(
        _ pattern: String,
        in value: String,
        with replacement: String
    ) -> String {
        guard let regex = try? NSRegularExpression(
            pattern: pattern,
            options: [.caseInsensitive]
        ) else { return value }
        return regex.stringByReplacingMatches(
            in: value,
            range: NSRange(value.startIndex..<value.endIndex, in: value),
            withTemplate: replacement
        )
    }
}
