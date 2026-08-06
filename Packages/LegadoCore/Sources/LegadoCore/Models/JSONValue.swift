public enum JSONValue: Codable, Equatable, Sendable {
    case null
    case bool(Bool)
    case integer(Int64)
    case number(Double)
    case string(String)
    case array([JSONValue])
    case object([String: JSONValue])

    public init(from decoder: Decoder) throws {
        if let container = try? decoder.container(keyedBy: DynamicCodingKey.self) {
            var values: [String: JSONValue] = [:]
            for key in container.allKeys {
                values[key.stringValue] = try container.decode(JSONValue.self, forKey: key)
            }
            self = .object(values)
            return
        }

        if var container = try? decoder.unkeyedContainer() {
            var values: [JSONValue] = []
            while !container.isAtEnd {
                values.append(try container.decode(JSONValue.self))
            }
            self = .array(values)
            return
        }

        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Int64.self) {
            self = .integer(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Unsupported JSON value"
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        switch self {
        case .null:
            var container = encoder.singleValueContainer()
            try container.encodeNil()
        case let .bool(value):
            var container = encoder.singleValueContainer()
            try container.encode(value)
        case let .integer(value):
            var container = encoder.singleValueContainer()
            try container.encode(value)
        case let .number(value):
            var container = encoder.singleValueContainer()
            try container.encode(value)
        case let .string(value):
            var container = encoder.singleValueContainer()
            try container.encode(value)
        case let .array(values):
            var container = encoder.unkeyedContainer()
            for value in values {
                try container.encode(value)
            }
        case let .object(values):
            var container = encoder.container(keyedBy: DynamicCodingKey.self)
            for (key, value) in values {
                try container.encode(value, forKey: DynamicCodingKey(key))
            }
        }
    }
}

struct DynamicCodingKey: CodingKey {
    let stringValue: String
    let intValue: Int?

    init(_ stringValue: String) {
        self.stringValue = stringValue
        self.intValue = nil
    }

    init?(stringValue: String) {
        self.init(stringValue)
    }

    init?(intValue: Int) {
        self.stringValue = String(intValue)
        self.intValue = intValue
    }
}

extension Decoder {
    func decodeExtraFields(excluding knownKeys: Set<String>) throws -> [String: JSONValue] {
        let container = try self.container(keyedBy: DynamicCodingKey.self)
        var fields: [String: JSONValue] = [:]
        for key in container.allKeys where !knownKeys.contains(key.stringValue) {
            fields[key.stringValue] = try container.decode(JSONValue.self, forKey: key)
        }
        return fields
    }
}

extension Encoder {
    func encodeExtraFields(
        _ fields: [String: JSONValue],
        excluding knownKeys: Set<String>
    ) throws {
        var container = self.container(keyedBy: DynamicCodingKey.self)
        for (key, value) in fields where !knownKeys.contains(key) {
            try container.encode(value, forKey: DynamicCodingKey(key))
        }
    }
}
