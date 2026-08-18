import SwiftUI

struct ReaderPagedContentView: View {
    let pages: [ReaderPage]
    let currentPageIndex: Int
    let fullText: String
    let annotations: [ReaderAnnotation]
    let settings: ReaderSettings
    let viewportWidth: CGFloat
    let canTurnPrevious: Bool
    let canTurnNext: Bool
    let turnPrevious: () -> Void
    let turnNext: () -> Void
    let toggleControls: () -> Void
    let onSelectionChanged: (ReaderTextSelection?) -> Void
    let selectionActive: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var turnState = ReaderPageTurnState()
    @State private var animationTask: Task<Void, Never>?

    var body: some View {
        ZStack {
            settings.theme.backgroundColor
            if let currentPage {
                ReaderPageView(
                    page: currentPage,
                    fullText: fullText,
                    annotations: annotations,
                    settings: settings,
                    onSelectionChanged: onSelectionChanged
                )
            }
            movingPage
        }
        .clipped()
        .contentShape(Rectangle())
        .simultaneousGesture(SpatialTapGesture().onEnded(handleTap))
        .simultaneousGesture(pageTurnGesture)
        .accessibilityAction(named: "上一页") { requestTurn(.previous) }
        .accessibilityAction(named: "下一页") { requestTurn(.next) }
        .onChange(of: viewportWidth) { _ in resetInteraction() }
        .onChange(of: currentPageIndex) { _ in resetInteraction() }
        .onChange(of: pages) { _ in resetInteraction() }
        .onChange(of: settings.pageTurnStyle) { _ in resetInteraction() }
        .onDisappear(perform: resetInteraction)
    }

    private var currentPage: ReaderPage? {
        guard pages.indices.contains(currentPageIndex) else { return nil }
        return pages[currentPageIndex]
    }

    @ViewBuilder
    private var movingPage: some View {
        if settings.pageTurnStyle == .cover,
           let direction = turnState.direction,
           let page = adjacentPage(for: direction) {
            ReaderPageView(
                page: page,
                fullText: fullText,
                annotations: annotations,
                settings: settings,
                onSelectionChanged: { _ in }
            )
                .offset(x: movingPageOffset(direction: direction))
                .allowsHitTesting(false)
                .shadow(
                    color: .black.opacity(turnState.translation == 0 ? 0 : 0.18),
                    radius: 6,
                    x: direction == .next ? -3 : 3
                )
                .accessibilityHidden(true)
        }
    }

    private var pageTurnGesture: some Gesture {
        DragGesture(minimumDistance: 10)
            .onChanged { value in
                guard !turnState.isAnimating else { return }
                guard !selectionActive else { return }
                let detected = ReaderPageTurnDecision.direction(for: value.translation)
                guard let detected, turnState.begin(direction: detected) else { return }
                turnState.translation = directionalTranslation(
                    value.translation.width,
                    direction: detected
                )
            }
            .onEnded { value in
                guard !selectionActive, !turnState.isAnimating,
                      let direction = turnState.direction else {
                    return
                }
                let decision = ReaderPageTurnDecision.evaluate(
                    direction: direction,
                    translation: value.translation.width,
                    predictedTranslation: value.predictedEndTranslation.width,
                    viewportWidth: viewportWidth,
                    canTurn: canTurn(direction)
                )
                switch decision {
                case let .complete(direction): completeTurn(direction)
                case .cancel, .ignored: cancelTurn()
                }
            }
    }

    private func handleTap(_ value: SpatialTapGesture.Value) {
        guard turnState.isIdle, !selectionActive else { return }
        let ratio = min(max(value.location.x / max(viewportWidth, 1), 0), 1)
        if ratio < 0.25 {
            requestTurn(.previous)
        } else if ratio > 0.75 {
            requestTurn(.next)
        } else {
            toggleControls()
        }
    }

    private func requestTurn(_ direction: ReaderPageTurnDirection) {
        guard turnState.isIdle, canTurn(direction) else { return }
        turnState.direction = direction
        if shouldAnimate(direction) {
            completeTurn(direction)
        } else {
            performTurn(direction)
            turnState.reset()
        }
    }

    private func completeTurn(_ direction: ReaderPageTurnDirection) {
        guard !turnState.isAnimating, canTurn(direction) else {
            cancelTurn()
            return
        }
        guard shouldAnimate(direction) else {
            performTurn(direction)
            turnState.reset()
            return
        }
        turnState.direction = direction
        turnState.isDragging = false
        turnState.isAnimating = true
        withAnimation(.easeOut(duration: 0.2)) {
            turnState.translation = direction == .next ? -viewportWidth : viewportWidth
        }
        animationTask?.cancel()
        animationTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(210))
            guard !Task.isCancelled else { return }
            performTurn(direction)
            turnState.reset()
            animationTask = nil
        }
    }

    private func cancelTurn() {
        guard !turnState.isAnimating else { return }
        turnState.isDragging = false
        turnState.isAnimating = true
        if settings.pageTurnStyle == .cover, !reduceMotion {
            withAnimation(.interactiveSpring(response: 0.22, dampingFraction: 0.88)) {
                turnState.translation = 0
            }
            animationTask?.cancel()
            animationTask = Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(230))
                guard !Task.isCancelled else { return }
                turnState.reset()
                animationTask = nil
            }
        } else {
            turnState.reset()
        }
    }

    private func performTurn(_ direction: ReaderPageTurnDirection) {
        switch direction {
        case .previous: turnPrevious()
        case .next: turnNext()
        }
    }

    private func canTurn(_ direction: ReaderPageTurnDirection) -> Bool {
        direction == .previous ? canTurnPrevious : canTurnNext
    }

    private func shouldAnimate(_ direction: ReaderPageTurnDirection) -> Bool {
        ReaderPageTurnAnimation.shouldAnimate(
            style: settings.pageTurnStyle,
            reduceMotion: reduceMotion,
            hasAdjacentPage: adjacentPage(for: direction) != nil
        )
    }

    private func adjacentPage(for direction: ReaderPageTurnDirection) -> ReaderPage? {
        let index = direction == .previous ? currentPageIndex - 1 : currentPageIndex + 1
        guard pages.indices.contains(index) else { return nil }
        return pages[index]
    }

    private func movingPageOffset(direction: ReaderPageTurnDirection) -> CGFloat {
        let available = canTurn(direction)
        let translation = available ? turnState.translation : turnState.translation * 0.2
        return direction == .next
            ? viewportWidth + translation
            : -viewportWidth + translation
    }

    private func directionalTranslation(
        _ translation: CGFloat,
        direction: ReaderPageTurnDirection
    ) -> CGFloat {
        switch direction {
        case .previous: max(translation, 0)
        case .next: min(translation, 0)
        }
    }

    private func resetInteraction() {
        animationTask?.cancel()
        animationTask = nil
        turnState.reset()
    }
}

private struct ReaderPageView: View {
    let page: ReaderPage
    let fullText: String
    let annotations: [ReaderAnnotation]
    let settings: ReaderSettings
    let onSelectionChanged: (ReaderTextSelection?) -> Void

    var body: some View {
        ReaderSelectableTextView(
            fullText: fullText,
            displayedText: page.text,
            displayedUTF16Range: page.utf16Range,
            annotations: annotations,
            settings: settings,
            onSelectionChanged: onSelectionChanged
        )
            .padding(.horizontal, CGFloat(settings.horizontalPadding))
            .padding(.vertical, 20)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(settings.theme.backgroundColor)
    }
}
