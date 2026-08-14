import Foundation

public protocol TextEncoder: Sendable {
    func encode(_ value: String, charset: String) throws -> Data
}

public struct FoundationTextEncoder: TextEncoder {
    public init() {}

    public func encode(_ value: String, charset: String) throws -> Data {
        try PlatformTextCodec.encode(value, charset: charset)
    }
}
