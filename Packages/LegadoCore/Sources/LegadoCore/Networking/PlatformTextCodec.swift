import Foundation

#if canImport(CoreFoundation)
import CoreFoundation
#endif

#if os(Windows)
import WinSDK
#endif

enum PlatformTextCodec {
    static func decode(_ data: Data, charset: String) throws -> String {
        let normalized = normalize(charset)
        if let encoding = foundationEncoding(normalized) {
            guard let value = String(data: removingUTF8BOM(from: data), encoding: encoding) else {
                throw HTTPError.decodingFailed(charset)
            }
            return value
        }
        guard let chinese = chineseEncoding(normalized) else {
            throw HTTPError.unsupportedCharset(charset)
        }
        let bytes = removingUTF8BOM(from: data)
        return decodeChineseLossy(bytes, encoding: chinese, charset: charset)
    }

    static func encode(_ value: String, charset: String) throws -> Data {
        let normalized = normalize(charset)
        if let encoding = foundationEncoding(normalized) {
            guard let data = value.data(using: encoding, allowLossyConversion: false) else {
                throw HTTPError.encodingFailed(charset)
            }
            return data
        }
        guard let chinese = chineseEncoding(normalized) else {
            throw HTTPError.unsupportedCharset(charset)
        }
        #if os(Windows)
        let data = try encodeWindows(value, codePage: chinese.windowsCodePage, charset: charset)
        if chinese.kind == .gb2312, !isValidEncodedData(data, kind: .gb2312) {
            throw HTTPError.encodingFailed(charset)
        }
        return data
        #else
        let encoding = foundationEncoding(for: chinese)
        guard let data = value.data(using: encoding, allowLossyConversion: false) else {
            throw HTTPError.encodingFailed(charset)
        }
        return data
        #endif
    }

    private static func normalize(_ charset: String) -> String {
        charset
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "_", with: "-")
    }

    private static func foundationEncoding(_ normalized: String) -> String.Encoding? {
        switch normalized {
        case "utf-8", "utf8": .utf8
        case "utf-16", "utf16", "unicode": .utf16
        case "utf-16le", "utf16le": .utf16LittleEndian
        case "utf-16be", "utf16be": .utf16BigEndian
        case "us-ascii", "ascii": .ascii
        case "iso-8859-1", "latin1", "latin-1": .isoLatin1
        default: nil
        }
    }

    private struct ChineseEncoding {
        let windowsCodePage: UInt32
        /// CFString external-encoding identifier, not an NSStringEncoding raw value.
        let coreFoundationRawValue: UInt32
        let kind: ChineseEncodingKind
    }

    private enum ChineseEncodingKind { case gb2312, gbk, gb18030, big5 }

    private static func chineseEncoding(_ normalized: String) -> ChineseEncoding? {
        switch normalized {
        case "gb2312", "gb-2312", "gb-2312-80":
            return ChineseEncoding(
                windowsCodePage: 936,
                coreFoundationRawValue: 0x0630,
                kind: .gb2312
            )
        case "gbk", "gbk-95", "cp936", "windows-936":
            return ChineseEncoding(
                windowsCodePage: 936,
                coreFoundationRawValue: 0x0631,
                kind: .gbk
            )
        case "gb18030", "gb-18030", "gb-18030-2000":
            return ChineseEncoding(
                windowsCodePage: 54_936,
                coreFoundationRawValue: 0x0632,
                kind: .gb18030
            )
        case "big5", "big-5", "cp950", "windows-950":
            return ChineseEncoding(
                windowsCodePage: 950,
                coreFoundationRawValue: 0x0A03,
                kind: .big5
            )
        default:
            return nil
        }
    }

    private static func removingUTF8BOM(from data: Data) -> Data {
        guard data.count >= 3, data.starts(with: [0xEF, 0xBB, 0xBF]) else { return data }
        return data.dropFirst(3)
    }

    private static func decodeChineseLossy(
        _ data: Data,
        encoding: ChineseEncoding,
        charset: String
    ) -> String {
        var result = ""
        let bytes = Array(data)
        var index = 0
        while index < bytes.count {
            let length = encodedUnitLength(bytes, at: index, kind: encoding.kind)
            guard length > 0 else {
                result.append("\u{FFFD}")
                index += 1
                continue
            }

            // Foundation/CoreFoundation Chinese codecs expect a complete byte
            // stream. Reinitializing the decoder for each two-byte character can
            // turn valid GBK/GB2312 input into replacement characters on Darwin.
            let runStart = index
            index += length
            while index < bytes.count {
                let nextLength = encodedUnitLength(bytes, at: index, kind: encoding.kind)
                guard nextLength > 0 else { break }
                index += nextLength
            }
            let run = Data(bytes[runStart..<index])
            if let decoded = decodeChineseRun(run, encoding: encoding, charset: charset) {
                result += decoded
            } else {
                appendLossyFallback(
                    for: Array(bytes[runStart..<index]),
                    encoding: encoding,
                    charset: charset,
                    to: &result
                )
            }
        }
        return result
    }

    private static func decodeChineseRun(
        _ data: Data,
        encoding: ChineseEncoding,
        charset: String
    ) -> String? {
        #if os(Windows)
        return try? decodeWindows(data, codePage: encoding.windowsCodePage, charset: charset)
        #else
        #if canImport(Darwin)
        if let coreFoundationEncoding = darwinCoreFoundationEncoding(for: encoding.kind) {
            return decodeDarwin(data, encoding: coreFoundationEncoding)
        }
        #endif
        return String(data: data, encoding: foundationEncoding(for: encoding))
        #endif
    }

    private static func appendLossyFallback(
        for bytes: [UInt8],
        encoding: ChineseEncoding,
        charset: String,
        to result: inout String
    ) {
        var index = 0
        while index < bytes.count {
            let length = encodedUnitLength(bytes, at: index, kind: encoding.kind)
            if bytes[index] < 0x80 {
                result += String(UnicodeScalar(bytes[index]))
            } else if length > 0,
                      let decoded = decodeChineseRun(
                        Data(bytes[index..<(index + length)]),
                        encoding: encoding,
                        charset: charset
                      ),
                      !decoded.isEmpty {
                result += decoded
            } else {
                result.append("\u{FFFD}")
            }
            index += max(length, 1)
        }
    }

    #if !os(Windows)
    #if canImport(Darwin)
    private static func darwinCoreFoundationEncoding(
        for kind: ChineseEncodingKind
    ) -> CFStringEncoding? {
        switch kind {
        case .gb2312:
            return CFStringEncoding(CFStringEncodings.GB_2312_80.rawValue)
        case .gbk:
            return CFStringEncoding(CFStringEncodings.GBK_95.rawValue)
        case .gb18030, .big5:
            return nil
        }
    }

    private static func decodeDarwin(
        _ data: Data,
        encoding: CFStringEncoding
    ) -> String? {
        guard !data.isEmpty else { return "" }
        return data.withUnsafeBytes { bytes in
            guard let source = bytes.baseAddress?.assumingMemoryBound(to: UInt8.self),
                  let decoded = CFStringCreateWithBytes(
                    kCFAllocatorDefault,
                    source,
                    bytes.count,
                    encoding,
                    false
                  ) else { return nil }
            return decoded as String
        }
    }
    #endif

    private static func foundationEncoding(for encoding: ChineseEncoding) -> String.Encoding {
        #if canImport(CoreFoundation)
        let cocoaEncoding = CFStringConvertEncodingToNSStringEncoding(
            CFStringEncoding(encoding.coreFoundationRawValue)
        )
        return String.Encoding(rawValue: cocoaEncoding)
        #else
        // Foundation's external NSString encodings use the CF identifier in the
        // low bits. This branch is only for platforms without CoreFoundation.
        return String.Encoding(rawValue: UInt(encoding.coreFoundationRawValue) | 0x8000_0000)
        #endif
    }
    #endif

    private static func encodedUnitLength(
        _ bytes: [UInt8],
        at index: Int,
        kind: ChineseEncodingKind
    ) -> Int {
        let first = bytes[index]
        if first < 0x80 { return 1 }
        guard index + 1 < bytes.count else { return 0 }
        let second = bytes[index + 1]
        switch kind {
        case .gb2312:
            return (0xA1...0xF7).contains(first) && (0xA1...0xFE).contains(second) ? 2 : 0
        case .gbk:
            return (0x81...0xFE).contains(first) &&
                (0x40...0xFE).contains(second) && second != 0x7F ? 2 : 0
        case .gb18030:
            if (0x81...0xFE).contains(first), (0x30...0x39).contains(second) {
                guard index + 3 < bytes.count,
                      (0x81...0xFE).contains(bytes[index + 2]),
                      (0x30...0x39).contains(bytes[index + 3]) else { return 0 }
                return 4
            }
            return (0x81...0xFE).contains(first) &&
                (0x40...0xFE).contains(second) && second != 0x7F ? 2 : 0
        case .big5:
            return (0x81...0xFE).contains(first) &&
                ((0x40...0x7E).contains(second) || (0xA1...0xFE).contains(second)) ? 2 : 0
        }
    }

    private static func isValidEncodedData(_ data: Data, kind: ChineseEncodingKind) -> Bool {
        let bytes = Array(data)
        var index = 0
        while index < bytes.count {
            let length = encodedUnitLength(bytes, at: index, kind: kind)
            guard length > 0, index + length <= bytes.count else { return false }
            index += length
        }
        return true
    }
    #if os(Windows)
    private static func decodeWindows(
        _ data: Data,
        codePage: UInt32,
        charset: String
    ) throws -> String {
        guard !data.isEmpty else { return "" }
        let required: Int32 = data.withUnsafeBytes { bytes in
            MultiByteToWideChar(
                codePage,
                0,
                bytes.baseAddress?.assumingMemoryBound(to: CChar.self),
                Int32(bytes.count),
                nil,
                0
            )
        }
        guard required > 0 else { throw HTTPError.decodingFailed(charset) }
        var output = [WCHAR](repeating: 0, count: Int(required))
        let written: Int32 = data.withUnsafeBytes { bytes in
            output.withUnsafeMutableBufferPointer { destination in
                MultiByteToWideChar(
                    codePage,
                    0,
                    bytes.baseAddress?.assumingMemoryBound(to: CChar.self),
                    Int32(bytes.count),
                    destination.baseAddress,
                    required
                )
            }
        }
        guard written == required else { throw HTTPError.decodingFailed(charset) }
        return String(decoding: output, as: UTF16.self)
    }

    private static func encodeWindows(
        _ value: String,
        codePage: UInt32,
        charset: String
    ) throws -> Data {
        let input = Array(value.utf16)
        guard !input.isEmpty else { return Data() }
        if codePage == 54_936 {
            let required: Int32 = input.withUnsafeBufferPointer { source in
                WideCharToMultiByte(
                    codePage, 0, source.baseAddress, Int32(source.count),
                    nil, 0, nil, nil
                )
            }
            guard required > 0 else { throw HTTPError.encodingFailed(charset) }
            var output = [CChar](repeating: 0, count: Int(required))
            let written: Int32 = input.withUnsafeBufferPointer { source in
                output.withUnsafeMutableBufferPointer { destination in
                    WideCharToMultiByte(
                        codePage, 0, source.baseAddress, Int32(source.count),
                        destination.baseAddress, required, nil, nil
                    )
                }
            }
            guard written == required else { throw HTTPError.encodingFailed(charset) }
            return output.withUnsafeBytes { Data($0) }
        }
        var usedDefaultCharacter = WindowsBool(false)
        let required: Int32 = input.withUnsafeBufferPointer { source in
            WideCharToMultiByte(
                codePage,
                0,
                source.baseAddress,
                Int32(source.count),
                nil,
                0,
                nil,
                &usedDefaultCharacter
            )
        }
        guard required > 0, !usedDefaultCharacter.boolValue else { throw HTTPError.encodingFailed(charset) }
        var output = [CChar](repeating: 0, count: Int(required))
        usedDefaultCharacter = WindowsBool(false)
        let written: Int32 = input.withUnsafeBufferPointer { source in
            output.withUnsafeMutableBufferPointer { destination in
                WideCharToMultiByte(
                    codePage,
                    0,
                    source.baseAddress,
                    Int32(source.count),
                    destination.baseAddress,
                    required,
                    nil,
                    &usedDefaultCharacter
                )
            }
        }
        guard written == required, !usedDefaultCharacter.boolValue else {
            throw HTTPError.encodingFailed(charset)
        }
        return output.withUnsafeBytes { Data($0) }
    }
    #endif
}
