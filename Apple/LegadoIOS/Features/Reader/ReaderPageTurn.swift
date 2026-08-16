import CoreGraphics

enum ReaderPageTurnDirection: Equatable {
    case previous
    case next
}

enum ReaderPageTurnDecision: Equatable {
    case ignored
    case cancel
    case complete(ReaderPageTurnDirection)

    static let completionThreshold: CGFloat = 0.25

    static func direction(for translation: CGSize) -> ReaderPageTurnDirection? {
        guard abs(translation.width) > abs(translation.height), translation.width != 0 else {
            return nil
        }
        return translation.width < 0 ? .next : .previous
    }

    static func evaluate(
        direction: ReaderPageTurnDirection?,
        translation: CGFloat,
        predictedTranslation: CGFloat,
        viewportWidth: CGFloat,
        canTurn: Bool
    ) -> ReaderPageTurnDecision {
        guard let direction, viewportWidth > 0 else { return .ignored }
        guard canTurn else { return .cancel }
        let rawProgress = min(abs(translation) / viewportWidth, 1)
        let predictedProgress = min(abs(predictedTranslation) / viewportWidth, 1)
        let rawDirectionMatches = direction == .next ? translation < 0 : translation > 0
        let predictedDirectionMatches = direction == .next
            ? predictedTranslation < 0
            : predictedTranslation > 0
        if (rawDirectionMatches && rawProgress >= completionThreshold)
            || (predictedDirectionMatches && predictedProgress >= completionThreshold) {
            return .complete(direction)
        }
        return .cancel
    }
}

struct ReaderPageTurnState: Equatable {
    var direction: ReaderPageTurnDirection?
    var translation: CGFloat = 0
    var isDragging = false
    var isAnimating = false

    var isIdle: Bool { direction == nil && !isDragging && !isAnimating }

    mutating func begin(direction: ReaderPageTurnDirection) -> Bool {
        guard !isAnimating else { return false }
        if self.direction == nil { self.direction = direction }
        guard self.direction == direction else { return false }
        isDragging = true
        return true
    }

    mutating func reset() { self = ReaderPageTurnState() }
}

enum ReaderPageTurnAnimation {
    static func shouldAnimate(
        style: ReaderPageTurnStyle,
        reduceMotion: Bool,
        hasAdjacentPage: Bool
    ) -> Bool {
        style == .cover && !reduceMotion && hasAdjacentPage
    }
}
