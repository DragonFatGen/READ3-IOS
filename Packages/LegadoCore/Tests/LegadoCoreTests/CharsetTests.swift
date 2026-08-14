import Foundation
import XCTest
@testable import LegadoCore

final class CharsetTests: XCTestCase {
    private let decoder = FoundationTextDecoder()
    private let encoder = FoundationTextEncoder()

    func testDecodesGBKAndGB2312FixturesAndAliases() throws {
        for (fixture, charset) in [
            ("gbk.hex", "GBK"),
            ("gb2312.hex", "gb2312")
        ] {
            XCTAssertEqual(try decoder.decode(try hexFixture(fixture), charset: charset), "中文阅读")
        }
        XCTAssertEqual(try decoder.decode(try hexFixture("gbk.hex"), charset: "cp936"), "中文阅读")
    }

    func testDecodesGB18030FourByteFixture() throws {
        XCTAssertEqual(
            try decoder.decode(try hexFixture("gb18030.hex"), charset: "GB18030"),
            "😀"
        )
    }

    func testDecodesBig5() throws {
        let bytes = try hexFixture("big5.hex")
        XCTAssertEqual(try decoder.decode(bytes, charset: "Big5"), "中文")
    }

    func testEncodesChineseCharsetsToExpectedBytes() throws {
        XCTAssertEqual(
            try encoder.encode("中文阅读", charset: "GBK"),
            try hexFixture("gbk.hex")
        )
        XCTAssertEqual(
            try encoder.encode("中文", charset: "Big5"),
            try hexFixture("big5.hex")
        )
        XCTAssertEqual(
            try encoder.encode("😀", charset: "GB18030"),
            try hexFixture("gb18030.hex")
        )
    }

    func testGB2312RejectsGBKOnlyCharacter() throws {
        XCTAssertEqual(
            try encoder.encode("镕", charset: "GBK"),
            try hexFixture("gbk-only.hex")
        )
        XCTAssertThrowsError(try encoder.encode("镕", charset: "GB2312")) {
            XCTAssertEqual($0 as? HTTPError, .encodingFailed("GB2312"))
        }
    }

    func testChineseDecoderMatchesAndroidReplacementForMalformedBytes() throws {
        XCTAssertEqual(
            try decoder.decode(try hexFixture("gbk-invalid.hex"), charset: "GBK"),
            "\u{FFFD} "
        )
    }

    func testUTF8BOMIsRemovedBeforeChineseCharsetDecode() throws {
        var bytes = Data([0xEF, 0xBB, 0xBF])
        bytes.append(try hexFixture("gbk.hex"))
        XCTAssertEqual(try decoder.decode(bytes, charset: "GBK"), "中文阅读")
    }

    func testUnrepresentableCharacterReturnsTypedEncodingError() throws {
        XCTAssertThrowsError(try encoder.encode("😀", charset: "GBK")) {
            XCTAssertEqual($0 as? HTTPError, .encodingFailed("GBK"))
        }
        XCTAssertThrowsError(try encoder.encode("中文", charset: "ASCII")) {
            XCTAssertEqual($0 as? HTTPError, .encodingFailed("ASCII"))
        }
    }

    func testUnknownCharsetRemainsTypedUnsupported() throws {
        XCTAssertThrowsError(try decoder.decode(Data(), charset: "x-private")) {
            XCTAssertEqual($0 as? HTTPError, .unsupportedCharset("x-private"))
        }
    }

    func testResponseCharsetPriorityIsExplicitThenHeaderThenHTMLMetaThenUTF8() throws {
        let url = try XCTUnwrap(URL(string: "https://fixture.invalid"))
        let gbk = try encoder.encode("中文阅读", charset: "GBK")
        let header = HTTPResponse(
            statusCode: 200,
            headers: HTTPHeaders(["Content-Type": "text/html; charset=GBK"]),
            data: gbk,
            finalURL: url
        )
        XCTAssertEqual(try header.text(), "中文阅读")

        let metaHTML = "<meta charset=GBK><p>中文阅读</p>"
        let meta = HTTPResponse(
            statusCode: 200,
            data: try encoder.encode(metaHTML, charset: "GBK"),
            finalURL: url
        )
        XCTAssertEqual(meta.htmlMetaCharset, "GBK")
        XCTAssertEqual(try meta.text(), metaHTML)

        let legacyMetaHTML =
            #"<meta http-equiv="Content-Type" content="text/html; charset=Big5"><p>中文</p>"#
        let legacyMeta = HTTPResponse(
            statusCode: 200,
            data: try encoder.encode(legacyMetaHTML, charset: "Big5"),
            finalURL: url
        )
        XCTAssertEqual(legacyMeta.htmlMetaCharset, "Big5")
        XCTAssertEqual(try legacyMeta.text(), legacyMetaHTML)

        let latin = HTTPResponse(
            statusCode: 200,
            headers: HTTPHeaders(["Content-Type": "text/plain; charset=GBK"]),
            data: try XCTUnwrap("café".data(using: .isoLatin1)),
            finalURL: url
        )
        XCTAssertEqual(try latin.text(explicitCharset: "iso-8859-1"), "café")

        let utf8 = HTTPResponse(statusCode: 200, data: Data("默认 UTF-8".utf8), finalURL: url)
        XCTAssertEqual(try utf8.text(), "默认 UTF-8")
    }

    func testContentTypeCharsetIsCaseInsensitiveQuotedAndAllowsExtraParameters() throws {
        let url = try XCTUnwrap(URL(string: "https://fixture.invalid"))
        let response = HTTPResponse(
            statusCode: 200,
            headers: HTTPHeaders([
                "Content-Type": "text/html; boundary=ignored; ChArSeT=\"GBK\"; version=1"
            ]),
            data: try encoder.encode("中文", charset: "GBK"),
            finalURL: url
        )
        XCTAssertEqual(response.contentTypeCharset, "GBK")
        XCTAssertEqual(try response.text(), "中文")
    }

    func testBOMIsRemovedWithoutOverridingExplicitCharsetPriority() throws {
        let url = try XCTUnwrap(URL(string: "https://fixture.invalid"))
        var data = Data([0xEF, 0xBB, 0xBF])
        data.append(try encoder.encode("中文", charset: "GBK"))
        let response = HTTPResponse(
            statusCode: 200,
            headers: HTTPHeaders(["Content-Type": "text/plain; charset=UTF-8"]),
            data: data,
            finalURL: url
        )
        XCTAssertEqual(try response.text(explicitCharset: "GBK"), "中文")
    }

    private func hexFixture(_ name: String) throws -> Data {
        let text = String(
            decoding: try FixtureLoader.data(named: name, directory: "charset"),
            as: UTF8.self
        )
        return Data(try text.split(whereSeparator: \.isWhitespace).map { value in
            guard let byte = UInt8(value, radix: 16) else { throw HexFixtureError.invalidByte(String(value)) }
            return byte
        })
    }
}

private enum HexFixtureError: Error { case invalidByte(String) }
