public struct HTTPHeader: Codable, Equatable, Sendable {
    public let name: String
    public let value: String

    public init(name: String, value: String) {
        self.name = name
        self.value = value
    }
}
public struct HTTPHeaders: Codable, Equatable, Sendable, Sequence {
    private var storage: [HTTPHeader]

    public init(_ headers: [HTTPHeader] = []) {
        storage = []
        for header in headers { self[header.name] = header.value }
    }

    public init(_ values: [String: String]) {
        self.init(values.keys.sorted().map { HTTPHeader(name: $0, value: values[$0]!) })
    }

    public subscript(name: String) -> String? {
        get { storage.last { $0.name.caseInsensitiveCompare(name) == .orderedSame }?.value }
        set {
            storage.removeAll { $0.name.caseInsensitiveCompare(name) == .orderedSame }
            if let newValue { storage.append(HTTPHeader(name: name, value: newValue)) }
        }
    }

    public var dictionary: [String: String] {
        Dictionary(uniqueKeysWithValues: storage.map { ($0.name, $0.value) })
    }

    public func makeIterator() -> IndexingIterator<[HTTPHeader]> {
        storage.makeIterator()
    }

    public mutating func merge(_ other: HTTPHeaders) {
        for header in other { self[header.name] = header.value }
    }
}
