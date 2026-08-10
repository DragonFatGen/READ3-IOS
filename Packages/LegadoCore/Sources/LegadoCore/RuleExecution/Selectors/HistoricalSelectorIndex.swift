struct HistoricalSelectorIndex: Equatable, Sendable {
    enum Mode: Equatable, Sendable {
        case include
        case exclude
        case none
    }

    enum Item: Equatable, Sendable {
        case index(Int)
        case range(start: Int?, end: Int?, step: Int)
    }

    let selector: String
    let mode: Mode
    let items: [Item]

    static func parse(_ rule: String) -> HistoricalSelectorIndex {
        let trimmed = rule.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasSuffix("]"), let open = trimmed.lastIndex(of: "[") {
            let bodyStart = trimmed.index(after: open)
            var body = String(trimmed[bodyStart..<trimmed.index(before: trimmed.endIndex)])
            let mode: Mode
            if body.hasPrefix("!") {
                mode = .exclude
                body.removeFirst()
            } else {
                mode = .include
            }
            let items = body.split(separator: ",", omittingEmptySubsequences: false).compactMap(parseItem)
            if !items.isEmpty {
                return HistoricalSelectorIndex(
                    selector: String(trimmed[..<open]).trimmingCharacters(in: .whitespacesAndNewlines),
                    mode: mode,
                    items: items
                )
            }
        }

        if let legacy = parseLegacy(trimmed) { return legacy }
        return HistoricalSelectorIndex(selector: trimmed, mode: .none, items: [])
    }

    func indexes(for count: Int) -> [Int] {
        guard count > 0 else { return [] }
        var ordered: [Int] = []
        func append(_ index: Int) {
            let resolved = index >= 0 ? index : count + index
            guard resolved >= 0, resolved < count, !ordered.contains(resolved) else { return }
            ordered.append(resolved)
        }

        for item in items {
            switch item {
            case let .index(index):
                append(index)
            case let .range(startValue, endValue, rawStep):
                let start = clamp(startValue, default: 0, count: count)
                let end = clamp(endValue, default: count - 1, count: count)
                if start == end || rawStep >= count {
                    append(start)
                    continue
                }
                let step = rawStep > 0 ? rawStep : ((-rawStep < count) ? rawStep + count : 1)
                guard step > 0 else { continue }
                if end > start {
                    var index = start
                    while index <= end { append(index); index += step }
                } else {
                    var index = start
                    while index >= end { append(index); index -= step }
                }
            }
        }
        return ordered
    }

    private static func parseItem(_ value: Substring) -> Item? {
        let fields = value.split(separator: ":", omittingEmptySubsequences: false)
        if fields.count == 1, let index = Int(fields[0].trimmingCharacters(in: .whitespaces)) {
            return .index(index)
        }
        guard fields.count == 2 || fields.count == 3 else { return nil }
        let start = optionalInt(fields[0])
        let end = optionalInt(fields[1])
        let step = fields.count == 3 ? (optionalInt(fields[2]) ?? 1) : 1
        return .range(start: start, end: end, step: step)
    }

    private static func optionalInt(_ value: Substring) -> Int? {
        let trimmed = value.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? nil : Int(trimmed)
    }

    private static func parseLegacy(_ rule: String) -> HistoricalSelectorIndex? {
        guard let delimiter = rule.lastIndex(where: { $0 == "." || $0 == "!" }) else { return nil }
        let suffix = rule[rule.index(after: delimiter)...]
        guard !suffix.isEmpty,
              suffix.allSatisfy({ $0.isNumber || $0 == "-" || $0 == ":" || $0.isWhitespace }) else {
            return nil
        }
        let values = suffix.split(separator: ":").compactMap {
            Int($0.trimmingCharacters(in: .whitespaces))
        }
        guard !values.isEmpty else { return nil }
        return HistoricalSelectorIndex(
            selector: String(rule[..<delimiter]),
            mode: rule[delimiter] == "!" ? .exclude : .include,
            items: values.map(Item.index)
        )
    }

    private func clamp(_ value: Int?, default defaultValue: Int, count: Int) -> Int {
        guard let value else { return defaultValue }
        if value >= 0 { return min(value, count - 1) }
        return max(0, count + value)
    }
}
