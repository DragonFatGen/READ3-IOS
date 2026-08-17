import XCTest
@testable import LegadoIOS

final class ReaderSpeechSegmenterTests: XCTestCase {
    private let segmenter = ReaderSpeechSegmenter(maximumUTF16Length: 40)

    func testEmptyTextProducesNoSegments() {
        XCTAssertTrue(segmenter.segments(in: "").isEmpty)
        XCTAssertTrue(segmenter.segments(in: " \n\t ").isEmpty)
    }

    func testChineseSentenceSegmentation() {
        let values = segmenter.segments(in: "第一句。第二句！第三句？")
        XCTAssertEqual(values.map(\.text), ["第一句。", "第二句！", "第三句？"])
    }

    func testEnglishPunctuationSegmentation() {
        let values = segmenter.segments(in: "First sentence. Second one! Is this third?")
        XCTAssertEqual(values.map(\.text), ["First sentence.", "Second one!", "Is this third?"])
    }

    func testParagraphsMaintainOrder() {
        let values = segmenter.segments(in: "第一段。\n\n第二段。\nThird paragraph.")
        XCTAssertEqual(values.map(\.text), ["第一段。", "第二段。", "Third paragraph."])
        XCTAssertEqual(values.map(\.startUTF16Offset), values.map(\.startUTF16Offset).sorted())
    }

    func testWhitespaceOnlySentencesAreIgnored() {
        let values = segmenter.segments(in: "\n\n正文。\n\t")
        XCTAssertEqual(values.map(\.text), ["正文。"])
    }

    func testOversizedSentenceSplitsSafely() {
        let text = String(repeating: "这是很长的句子内容", count: 20) + "。"
        let values = segmenter.segments(in: text)
        XCTAssertGreaterThan(values.count, 1)
        XCTAssertTrue(values.allSatisfy { !$0.text.isEmpty && $0.text.utf16.count <= 42 })
        XCTAssertEqual(values.map(\.text).joined(), text)
    }

    func testOversizedEmojiDoesNotSplitComposedCharacter() {
        let text = String(repeating: "👨‍👩‍👧‍👦", count: 12)
        let values = ReaderSpeechSegmenter(maximumUTF16Length: 32).segments(in: text)
        XCTAssertEqual(values.map(\.text).joined(), text)
        XCTAssertTrue(values.allSatisfy { !$0.text.contains("�") })
    }

    func testProgressZeroSelectsFirstSegment() {
        assertIndex(progress: 0, expected: 0)
    }

    func testProgressMiddleSelectsContainingSegment() {
        let text = "短句。这里是明显更长一些的第二句话。末句。"
        let values = ReaderSpeechSegmenter().segments(in: text)
        let offset = Double(values[1].startUTF16Offset + 2) / Double(text.utf16.count)
        XCTAssertEqual(
            ReaderSpeechSegmenter().segmentIndex(
                forNormalizedProgress: offset,
                in: values,
                totalUTF16Length: text.utf16.count
            ),
            1
        )
    }

    func testProgressNearEndSelectsLastSegment() {
        assertIndex(progress: 0.999, expected: 2)
    }

    private func assertIndex(progress: Double, expected: Int) {
        let text = "第一句。第二句。第三句。"
        let values = ReaderSpeechSegmenter().segments(in: text)
        XCTAssertEqual(
            ReaderSpeechSegmenter().segmentIndex(
                forNormalizedProgress: progress,
                in: values,
                totalUTF16Length: text.utf16.count
            ),
            expected
        )
    }
}
