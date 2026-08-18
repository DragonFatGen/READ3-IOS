import Foundation

enum ReaderAnnotationStyle: String, CaseIterable, Codable, Equatable, Sendable {
    case yellow
    case green
    case blue
    case pink

    var title: String {
        switch self {
        case .yellow: "黄色"
        case .green: "绿色"
        case .blue: "蓝色"
        case .pink: "粉色"
        }
    }
}

struct ReaderAnnotation: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    let bookID: String
    let sourceIdentity: String
    let bookIdentity: String
    let chapterIndex: Int
    let chapterURL: String
    let chapterName: String
    let utf16Location: Int
    let utf16Length: Int
    let chapterUTF16Length: Int
    let selectedText: String
    var style: ReaderAnnotationStyle
    var note: String?
    let createdAt: Date
    var updatedAt: Date

    var utf16Range: Range<Int> {
        guard utf16Location >= 0,
              utf16Length > 0,
              utf16Location <= Int.max - utf16Length else {
            return 0..<0
        }
        return utf16Location..<(utf16Location + utf16Length)
    }

    var normalizedProgress: Double {
        guard chapterUTF16Length > 0 else { return 0 }
        return min(max(Double(utf16Location) / Double(chapterUTF16Length), 0), 1)
    }

    func resolvedRange(in content: String) -> NSRange? {
        let source = content as NSString
        guard utf16Location >= 0,
              utf16Length > 0,
              !selectedText.isEmpty else { return nil }
        if utf16Location <= source.length,
           utf16Length <= source.length - utf16Location {
            let saved = NSRange(location: utf16Location, length: utf16Length)
            if Range(saved, in: content) != nil,
               source.substring(with: saved) == selectedText {
                return saved
            }
        }

        var matches: [NSRange] = []
        var search = NSRange(location: 0, length: source.length)
        while search.length > 0 {
            let match = source.range(of: selectedText, options: [], range: search)
            guard match.location != NSNotFound else { break }
            if Range(match, in: content) != nil { matches.append(match) }
            let next = NSMaxRange(match)
            guard next < source.length else { break }
            search = NSRange(location: next, length: source.length - next)
        }
        return matches.min {
            abs($0.location - utf16Location) < abs($1.location - utf16Location)
        }
    }
}

struct ReaderTextSelection: Equatable {
    let utf16Range: NSRange
    let selectedText: String
}

struct ReaderAnnotationRenderSpan: Equatable {
    let annotationID: UUID
    let localUTF16Range: NSRange
    let style: ReaderAnnotationStyle
}

enum ReaderAnnotationRangeMapper {
    static func spans(
        annotations: [ReaderAnnotation],
        fullText: String,
        displayedUTF16Range: Range<Int>
    ) -> [ReaderAnnotationRenderSpan] {
        annotations.compactMap { annotation in
            guard let resolved = annotation.resolvedRange(in: fullText) else { return nil }
            let lower = max(resolved.location, displayedUTF16Range.lowerBound)
            let upper = min(NSMaxRange(resolved), displayedUTF16Range.upperBound)
            guard lower < upper else { return nil }
            return ReaderAnnotationRenderSpan(
                annotationID: annotation.id,
                localUTF16Range: NSRange(
                    location: lower - displayedUTF16Range.lowerBound,
                    length: upper - lower
                ),
                style: annotation.style
            )
        }
    }
}
