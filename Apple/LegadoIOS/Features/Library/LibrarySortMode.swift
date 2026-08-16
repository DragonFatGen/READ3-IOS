import Combine
import Foundation

enum LibrarySortMode: String, CaseIterable, Identifiable {
    case recentlyRead
    case recentlyAdded
    case title
    case progress

    var id: String { rawValue }

    var title: String {
        switch self {
        case .recentlyRead: "最近阅读"
        case .recentlyAdded: "最近加入"
        case .title: "书名"
        case .progress: "阅读进度"
        }
    }
}

@MainActor
final class LibrarySortPreference: ObservableObject {
    @Published var mode: LibrarySortMode { didSet { defaults.set(mode.rawValue, forKey: storageKey) } }

    private let defaults: UserDefaults
    private let storageKey: String

    init(defaults: UserDefaults = .standard, storageKey: String = "library.sort.mode") {
        self.defaults = defaults
        self.storageKey = storageKey
        mode = defaults.string(forKey: storageKey).flatMap(LibrarySortMode.init(rawValue:))
            ?? .recentlyRead
    }
}

extension Array where Element == LibraryBook {
    func sorted(by mode: LibrarySortMode) -> [LibraryBook] {
        sorted { lhs, rhs in
            switch mode {
            case .recentlyRead:
                switch (lhs.lastReadAt, rhs.lastReadAt) {
                case let (lhsDate?, rhsDate?) where lhsDate != rhsDate:
                    return lhsDate > rhsDate
                case (_?, nil): return true
                case (nil, _?): return false
                default: break
                }
                if lhs.addedAt != rhs.addedAt { return lhs.addedAt > rhs.addedAt }
            case .recentlyAdded:
                if lhs.addedAt != rhs.addedAt { return lhs.addedAt > rhs.addedAt }
            case .title:
                let comparison = lhs.name.localizedStandardCompare(rhs.name)
                if comparison != .orderedSame { return comparison == .orderedAscending }
            case .progress:
                if lhs.progress?.overallProgress != rhs.progress?.overallProgress {
                    return (lhs.progress?.overallProgress ?? -1) > (rhs.progress?.overallProgress ?? -1)
                }
            }
            return lhs.id < rhs.id
        }
    }
}
