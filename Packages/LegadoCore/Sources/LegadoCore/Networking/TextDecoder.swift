import Foundation

public protocol TextDecoder: Sendable {
    func decode(_ data: Data, charset: String) throws -> String
}

public struct FoundationTextDecoder: TextDecoder {
    public init() {}

    public func decode(_ data: Data, charset: String) throws -> String {
        let normalized = charset
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "_", with: "-")
        let encoding: String.Encoding
        switch normalized {
        case "utf-8", "utf8": encoding = .utf8
        case "utf-16", "utf16": encoding = .utf16
        case "utf-16le", "utf16le": encoding = .utf16LittleEndian
        case "utf-16be", "utf16be": encoding = .utf16BigEndian
        case "us-ascii", "ascii": encoding = .ascii
        case "iso-8859-1", "latin1": encoding = .isoLatin1
        case "gbk", "gb2312", "gb18030", "big5":
            throw HTTPError.unsupportedCharset(charset)
        default:
            throw HTTPError.unsupportedCharset(charset)
        }
        guard let value = String(data: removingUTF8BOM(from: data), encoding: encoding) else {
            throw HTTPError.decodingFailed(charset)
        }
        return value
    }

    private func removingUTF8BOM(from data: Data) -> Data {
        guard data.count >= 3, data.starts(with: [0xEF, 0xBB, 0xBF]) else { return data }
        return data.dropFirst(3)
    }
}
