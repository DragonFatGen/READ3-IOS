import Foundation

public protocol TextDecoder: Sendable {
    func decode(_ data: Data, charset: String) throws -> String
}

public struct FoundationTextDecoder: TextDecoder {
    public init() {}

    public func decode(_ data: Data, charset: String) throws -> String {
        try PlatformTextCodec.decode(data, charset: charset)
    }
}
