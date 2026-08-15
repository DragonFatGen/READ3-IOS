import Foundation
import UIKit

struct ReaderPage: Identifiable, Equatable, Sendable {
    let index: Int
    let utf16Range: Range<Int>
    let text: String

    var id: Int { index }
}

struct PaginationConfiguration: Equatable, Sendable {
    let size: CGSize
    let fontSize: CGFloat
    let lineSpacing: CGFloat
    let horizontalPadding: CGFloat
    let verticalPadding: CGFloat

    var availableTextSize: CGSize {
        CGSize(
            width: max(size.width - horizontalPadding * 2, 1),
            height: max(size.height - verticalPadding * 2, 1)
        )
    }
}

protocol ReaderPaginating: Sendable {
    func paginate(text: String, configuration: PaginationConfiguration) async -> [ReaderPage]
}

actor TextKitReaderPaginator: ReaderPaginating {
    func paginate(text: String, configuration: PaginationConfiguration) async -> [ReaderPage] {
        guard !text.isEmpty else {
            return [ReaderPage(index: 0, utf16Range: 0..<0, text: "")]
        }

        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = configuration.lineSpacing
        let storage = NSTextStorage(
            string: text,
            attributes: [
                .font: UIFont.systemFont(ofSize: configuration.fontSize),
                .paragraphStyle: paragraph
            ]
        )
        let layoutManager = NSLayoutManager()
        storage.addLayoutManager(layoutManager)
        let source = text as NSString
        var pages: [ReaderPage] = []
        var consumedUTF16 = 0

        while consumedUTF16 < source.length {
            let container = NSTextContainer(size: configuration.availableTextSize)
            container.lineFragmentPadding = 0
            container.maximumNumberOfLines = 0
            layoutManager.addTextContainer(container)
            layoutManager.ensureLayout(for: container)

            let glyphRange = layoutManager.glyphRange(for: container)
            let characterRange = layoutManager.characterRange(
                forGlyphRange: glyphRange,
                actualGlyphRange: nil
            )
            guard characterRange.length > 0 else { break }
            let upperBound = min(NSMaxRange(characterRange), source.length)
            guard upperBound > consumedUTF16 else { break }
            let safeRange = NSRange(
                location: consumedUTF16,
                length: upperBound - consumedUTF16
            )
            pages.append(ReaderPage(
                index: pages.count,
                utf16Range: safeRange.location..<NSMaxRange(safeRange),
                text: source.substring(with: safeRange)
            ))
            consumedUTF16 = upperBound
        }

        if consumedUTF16 < source.length {
            let remaining = NSRange(location: consumedUTF16, length: source.length - consumedUTF16)
            pages.append(ReaderPage(
                index: pages.count,
                utf16Range: remaining.location..<NSMaxRange(remaining),
                text: source.substring(with: remaining)
            ))
        }
        return pages.isEmpty
            ? [ReaderPage(index: 0, utf16Range: 0..<source.length, text: text)]
            : pages
    }
}

enum ChapterEntryPosition: Equatable {
    case start
    case end
    case restore
}
