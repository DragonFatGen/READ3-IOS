import Foundation

struct ReaderSpeechSegmenter: Sendable {
    let maximumUTF16Length: Int

    init(maximumUTF16Length: Int = 800) {
        self.maximumUTF16Length = max(maximumUTF16Length, 32)
    }

    func segments(in text: String) -> [ReaderSpeechSegment] {
        guard !text.isEmpty else { return [] }
        let source = text as NSString
        var sentenceRanges: [NSRange] = []
        text.enumerateSubstrings(
            in: text.startIndex..<text.endIndex,
            options: [.bySentences, .substringNotRequired]
        ) { _, range, _, _ in
            let lower = range.lowerBound.utf16Offset(in: text)
            let upper = range.upperBound.utf16Offset(in: text)
            sentenceRanges.append(NSRange(location: lower, length: upper - lower))
        }

        if sentenceRanges.isEmpty {
            sentenceRanges = [NSRange(location: 0, length: source.length)]
        }

        return sentenceRanges.flatMap { splitAndTrim($0, source: source) }
    }

    func segmentIndex(forNormalizedProgress progress: Double, in segments: [ReaderSpeechSegment], totalUTF16Length: Int) -> Int? {
        guard !segments.isEmpty else { return nil }
        let length = max(totalUTF16Length, 1)
        let offset = min(max(Int((min(max(progress, 0), 1) * Double(length)).rounded()), 0), length)
        if let containing = segments.firstIndex(where: { $0.contains(utf16Offset: offset) }) {
            return containing
        }
        return segments.firstIndex(where: { $0.startUTF16Offset >= offset }) ?? (segments.count - 1)
    }

    private func splitAndTrim(_ rawRange: NSRange, source: NSString) -> [ReaderSpeechSegment] {
        guard let trimmed = trimmedRange(rawRange, source: source) else { return [] }
        var result: [ReaderSpeechSegment] = []
        var cursor = trimmed.location
        let end = NSMaxRange(trimmed)

        while cursor < end {
            let proposedEnd = min(cursor + maximumUTF16Length, end)
            var pieceEnd = proposedEnd
            if proposedEnd < end {
                let searchStart = cursor + maximumUTF16Length * 3 / 5
                let searchRange = NSRange(location: searchStart, length: proposedEnd - searchStart)
                let boundary = source.rangeOfCharacter(
                    from: CharacterSet.whitespacesAndNewlines.union(
                        CharacterSet(charactersIn: "，。！？；：,.!?;:")
                    ),
                    options: .backwards,
                    range: searchRange
                )
                if boundary.location != NSNotFound { pieceEnd = NSMaxRange(boundary) }
            }
            let safe = source.rangeOfComposedCharacterSequences(
                for: NSRange(location: cursor, length: max(pieceEnd - cursor, 1))
            )
            guard safe.length > 0 else { break }
            if let clean = trimmedRange(safe, source: source) {
                result.append(ReaderSpeechSegment(
                    text: source.substring(with: clean),
                    startUTF16Offset: clean.location,
                    endUTF16Offset: NSMaxRange(clean)
                ))
            }
            cursor = NSMaxRange(safe)
        }
        return result
    }

    private func trimmedRange(_ range: NSRange, source: NSString) -> NSRange? {
        guard range.length > 0 else { return nil }
        let nonWhitespace = CharacterSet.whitespacesAndNewlines.inverted
        let first = source.rangeOfCharacter(from: nonWhitespace, range: range)
        guard first.location != NSNotFound else { return nil }
        let last = source.rangeOfCharacter(from: nonWhitespace, options: .backwards, range: range)
        return NSRange(location: first.location, length: NSMaxRange(last) - first.location)
    }
}
