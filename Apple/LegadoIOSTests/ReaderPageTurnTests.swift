import CoreGraphics
import XCTest
@testable import LegadoIOS

final class ReaderPageTurnTests: XCTestCase {
    func testHorizontalDirectionAndVerticalGesture() {
        XCTAssertEqual(
            ReaderPageTurnDecision.direction(for: CGSize(width: -60, height: 10)),
            .next
        )
        XCTAssertEqual(
            ReaderPageTurnDecision.direction(for: CGSize(width: 60, height: 10)),
            .previous
        )
        XCTAssertNil(ReaderPageTurnDecision.direction(for: CGSize(width: 10, height: 60)))
    }

    func testThresholdCompletesOrCancels() {
        XCTAssertEqual(decision(translation: -70, predicted: -70), .cancel)
        XCTAssertEqual(decision(translation: -80, predicted: -80), .complete(.next))
    }

    func testFastFlickCompletesBelowRawThreshold() {
        XCTAssertEqual(decision(translation: -30, predicted: -120), .complete(.next))
        XCTAssertEqual(
            ReaderPageTurnDecision.evaluate(
                direction: .previous,
                translation: 30,
                predictedTranslation: 120,
                viewportWidth: 320,
                canTurn: true
            ),
            .complete(.previous)
        )
    }

    func testLockedDirectionDoesNotCompleteAfterReversing() {
        XCTAssertEqual(
            ReaderPageTurnDecision.evaluate(
                direction: .next,
                translation: 120,
                predictedTranslation: 160,
                viewportWidth: 320,
                canTurn: true
            ),
            .cancel
        )
    }

    func testBoundaryBlocksTurn() {
        XCTAssertEqual(
            ReaderPageTurnDecision.evaluate(
                direction: .previous,
                translation: 200,
                predictedTranslation: 260,
                viewportWidth: 320,
                canTurn: false
            ),
            .cancel
        )
        XCTAssertEqual(
            ReaderPageTurnDecision.evaluate(
                direction: .next,
                translation: -200,
                predictedTranslation: -260,
                viewportWidth: 320,
                canTurn: false
            ),
            .cancel
        )
    }

    func testDirectionLocksAndAnimationBlocksRepeatedGesture() {
        var state = ReaderPageTurnState()
        XCTAssertTrue(state.begin(direction: .next))
        XCTAssertFalse(state.begin(direction: .previous))
        state.isAnimating = true
        XCTAssertFalse(state.begin(direction: .next))
        state.reset()
        XCTAssertTrue(state.isIdle)
    }

    func testReducedMotionAndNoneDisableCoverAnimation() {
        XCTAssertTrue(ReaderPageTurnAnimation.shouldAnimate(
            style: .cover, reduceMotion: false, hasAdjacentPage: true
        ))
        XCTAssertFalse(ReaderPageTurnAnimation.shouldAnimate(
            style: .cover, reduceMotion: true, hasAdjacentPage: true
        ))
        XCTAssertFalse(ReaderPageTurnAnimation.shouldAnimate(
            style: .none, reduceMotion: false, hasAdjacentPage: true
        ))
        XCTAssertFalse(ReaderPageTurnAnimation.shouldAnimate(
            style: .cover, reduceMotion: false, hasAdjacentPage: false
        ))
    }

    private func decision(translation: CGFloat, predicted: CGFloat) -> ReaderPageTurnDecision {
        ReaderPageTurnDecision.evaluate(
            direction: .next,
            translation: translation,
            predictedTranslation: predicted,
            viewportWidth: 320,
            canTurn: true
        )
    }
}
