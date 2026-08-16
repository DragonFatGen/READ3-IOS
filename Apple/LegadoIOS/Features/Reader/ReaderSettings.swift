import SwiftUI

enum ReaderLayoutMode: String, CaseIterable, Codable, Hashable {
    case scroll
    case paged

    var title: String {
        switch self {
        case .scroll: "滚动"
        case .paged: "分页"
        }
    }
}

enum ReaderPageTurnStyle: String, CaseIterable, Codable, Hashable {
    case none
    case cover

    var title: String {
        switch self {
        case .none: "无动画"
        case .cover: "覆盖翻页"
        }
    }
}

enum ReaderTheme: String, CaseIterable, Codable, Hashable {
    case system
    case light
    case sepia
    case dark

    var title: String {
        switch self {
        case .system: "跟随系统"
        case .light: "白色"
        case .sepia: "护眼"
        case .dark: "夜间"
        }
    }

    var backgroundColor: Color {
        switch self {
        case .system: Color(uiColor: .systemBackground)
        case .light: Color(red: 0.98, green: 0.98, blue: 0.97)
        case .sepia: Color(red: 0.91, green: 0.90, blue: 0.77)
        case .dark: Color(red: 0.08, green: 0.09, blue: 0.10)
        }
    }

    var foregroundColor: Color {
        switch self {
        case .system: Color(uiColor: .label)
        case .light: Color(red: 0.10, green: 0.10, blue: 0.10)
        case .sepia: Color(red: 0.20, green: 0.18, blue: 0.13)
        case .dark: Color(red: 0.84, green: 0.84, blue: 0.82)
        }
    }

    var secondaryColor: Color { foregroundColor.opacity(0.65) }
}

struct ReaderSettings: Equatable {
    static let fontSizeRange = 14.0...32.0
    static let lineSpacingRange = 2.0...18.0
    static let horizontalPaddingRange = 12.0...40.0

    var fontSize: Double
    var lineSpacing: Double
    var horizontalPadding: Double
    var theme: ReaderTheme
    var layoutMode: ReaderLayoutMode
    var pageTurnStyle: ReaderPageTurnStyle

    static let `default` = ReaderSettings(
        fontSize: 19,
        lineSpacing: 8,
        horizontalPadding: 20,
        theme: .system,
        layoutMode: .scroll,
        pageTurnStyle: .cover
    )

    func clamped() -> ReaderSettings {
        ReaderSettings(
            fontSize: min(max(fontSize, Self.fontSizeRange.lowerBound), Self.fontSizeRange.upperBound),
            lineSpacing: min(max(lineSpacing, Self.lineSpacingRange.lowerBound), Self.lineSpacingRange.upperBound),
            horizontalPadding: min(
                max(horizontalPadding, Self.horizontalPaddingRange.lowerBound),
                Self.horizontalPaddingRange.upperBound
            ),
            theme: theme,
            layoutMode: layoutMode,
            pageTurnStyle: pageTurnStyle
        )
    }
}
