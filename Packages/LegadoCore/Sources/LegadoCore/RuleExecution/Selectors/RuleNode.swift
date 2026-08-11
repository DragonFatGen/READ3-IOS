import Foundation
import SwiftSoup

/// An opaque selector node. Third-party parser types never cross this public boundary.
public struct RuleNode: @unchecked Sendable, Equatable {
    public enum Kind: String, Sendable, Equatable {
        case html
        case json
    }

    enum Storage {
        case html(HTMLRuleNode)
        case json(JSONValue)
    }

    let storage: Storage

    public var kind: Kind {
        switch storage {
        case .html: .html
        case .json: .json
        }
    }

    public static func == (lhs: RuleNode, rhs: RuleNode) -> Bool {
        switch (lhs.storage, rhs.storage) {
        case let (.html(lhs), .html(rhs)):
            return lhs.owner === rhs.owner && lhs.element === rhs.element
        case let (.json(lhs), .json(rhs)):
            return lhs == rhs
        default:
            return false
        }
    }

    func scalarString() throws -> String {
        switch storage {
        case let .html(node):
            return try node.owner.withLock { try node.element.outerHtml() }
        case let .json(value):
            return value.deterministicRuleString
        }
    }
}

public struct RuleNodeCollection: Sendable, Equatable {
    public let nodes: [RuleNode]

    public init(nodes: [RuleNode]) {
        self.nodes = nodes
    }

    public var isEmpty: Bool { nodes.isEmpty }
    public var count: Int { nodes.count }
}

final class HTMLRuleNodeOwner: @unchecked Sendable {
    private let lock = NSRecursiveLock()
    private let retainedRoots: [Element]

    init(retaining roots: [Element]) {
        retainedRoots = roots
    }

    func withLock<T>(_ body: () throws -> T) rethrows -> T {
        lock.lock()
        defer { lock.unlock() }
        return try body()
    }
}

struct HTMLRuleNode {
    let owner: HTMLRuleNodeOwner
    let element: Element
}

extension JSONValue {
    var deterministicRuleString: String {
        switch self {
        case .null: return "null"
        case let .bool(value): return value ? "true" : "false"
        case let .integer(value): return String(value)
        case let .number(value): return value.isFinite ? String(value) : "null"
        case let .string(value): return value
        case .array, .object:
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
            return (try? String(decoding: encoder.encode(self), as: UTF8.self)) ?? "null"
        }
    }
}
