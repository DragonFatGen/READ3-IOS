import SwiftUI
import UIKit

struct ReaderSelectableTextView: UIViewRepresentable {
    let fullText: String
    let displayedText: String
    let displayedUTF16Range: Range<Int>
    let annotations: [ReaderAnnotation]
    let settings: ReaderSettings
    let onSelectionChanged: (ReaderTextSelection?) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(
            fullText: fullText,
            displayedUTF16Range: displayedUTF16Range,
            onSelectionChanged: onSelectionChanged
        )
    }

    func makeUIView(context: Context) -> UITextView {
        let textView = UITextView()
        textView.delegate = context.coordinator
        textView.isEditable = false
        textView.isSelectable = true
        textView.isScrollEnabled = false
        textView.backgroundColor = .clear
        textView.textContainerInset = .zero
        textView.textContainer.lineFragmentPadding = 0
        textView.adjustsFontForContentSizeCategory = false
        textView.accessibilityLabel = "阅读正文"
        return textView
    }

    func updateUIView(_ textView: UITextView, context: Context) {
        context.coordinator.onSelectionChanged = onSelectionChanged
        context.coordinator.fullText = fullText
        context.coordinator.displayedUTF16Range = displayedUTF16Range
        let selection = textView.selectedRange
        context.coordinator.isUpdating = true
        textView.attributedText = attributedText()
        if NSMaxRange(selection) <= (displayedText as NSString).length {
            textView.selectedRange = selection
        }
        context.coordinator.isUpdating = false
    }

    func sizeThatFits(
        _ proposal: ProposedViewSize,
        uiView: UITextView,
        context: Context
    ) -> CGSize? {
        guard let width = proposal.width else { return nil }
        let fitting = uiView.sizeThatFits(
            CGSize(width: width, height: CGFloat.greatestFiniteMagnitude)
        )
        return CGSize(width: width, height: max(fitting.height, 1))
    }

    private func attributedText() -> NSAttributedString {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = CGFloat(settings.lineSpacing)
        let attributed = NSMutableAttributedString(
            string: displayedText,
            attributes: [
                .font: UIFont.systemFont(ofSize: CGFloat(settings.fontSize)),
                .foregroundColor: UIColor(settings.theme.foregroundColor),
                .paragraphStyle: paragraph
            ]
        )
        let spans = ReaderAnnotationRangeMapper.spans(
            annotations: annotations,
            fullText: fullText,
            displayedUTF16Range: displayedUTF16Range
        )
        for span in spans where NSMaxRange(span.localUTF16Range) <= attributed.length {
            attributed.addAttribute(
                .backgroundColor,
                value: span.style.uiColor,
                range: span.localUTF16Range
            )
        }
        return attributed
    }

    @MainActor
    final class Coordinator: NSObject, UITextViewDelegate {
        var fullText: String
        var displayedUTF16Range: Range<Int>
        var onSelectionChanged: (ReaderTextSelection?) -> Void
        var isUpdating = false

        init(
            fullText: String,
            displayedUTF16Range: Range<Int>,
            onSelectionChanged: @escaping (ReaderTextSelection?) -> Void
        ) {
            self.fullText = fullText
            self.displayedUTF16Range = displayedUTF16Range
            self.onSelectionChanged = onSelectionChanged
        }

        func textViewDidChangeSelection(_ textView: UITextView) {
            guard !isUpdating, textView.isFirstResponder else { return }
            let localRange = textView.selectedRange
            guard localRange.length > 0,
                  NSMaxRange(localRange) <= ((textView.text ?? "") as NSString).length else {
                onSelectionChanged(nil)
                return
            }
            let globalRange = NSRange(
                location: displayedUTF16Range.lowerBound + localRange.location,
                length: localRange.length
            )
            guard NSMaxRange(globalRange) <= (fullText as NSString).length else {
                onSelectionChanged(nil)
                return
            }
            let selected = (fullText as NSString).substring(with: globalRange)
            onSelectionChanged(ReaderTextSelection(
                utf16Range: globalRange,
                selectedText: selected
            ))
        }
    }
}

extension ReaderAnnotationStyle {
    var color: Color {
        switch self {
        case .yellow: Color.yellow.opacity(0.42)
        case .green: Color.green.opacity(0.34)
        case .blue: Color.blue.opacity(0.28)
        case .pink: Color.pink.opacity(0.32)
        }
    }

    var uiColor: UIColor {
        switch self {
        case .yellow: UIColor.systemYellow.withAlphaComponent(0.42)
        case .green: UIColor.systemGreen.withAlphaComponent(0.34)
        case .blue: UIColor.systemBlue.withAlphaComponent(0.28)
        case .pink: UIColor.systemPink.withAlphaComponent(0.32)
        }
    }
}
