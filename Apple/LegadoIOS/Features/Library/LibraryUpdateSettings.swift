import Foundation

enum LibraryUpdateInterval: String, CaseIterable, Identifiable, Codable {
    case everyHour
    case every6Hours
    case every12Hours
    case daily

    var id: String { rawValue }

    var duration: TimeInterval {
        switch self {
        case .everyHour: 60 * 60
        case .every6Hours: 6 * 60 * 60
        case .every12Hours: 12 * 60 * 60
        case .daily: 24 * 60 * 60
        }
    }

    var title: String {
        switch self {
        case .everyHour: "每小时"
        case .every6Hours: "每 6 小时"
        case .every12Hours: "每 12 小时"
        case .daily: "每天"
        }
    }
}

struct LibraryUpdateSettings: Equatable {
    var automaticCheckEnabled: Bool
    var automaticCheckInterval: LibraryUpdateInterval
    var notificationEnabled: Bool

    static let `default` = LibraryUpdateSettings(
        automaticCheckEnabled: true,
        automaticCheckInterval: .every6Hours,
        notificationEnabled: false
    )
}

struct LibraryAutoUpdatePolicy {
    func shouldCheck(
        now: Date,
        lastAutomaticCheckAt: Date?,
        settings: LibraryUpdateSettings
    ) -> Bool {
        guard settings.automaticCheckEnabled else { return false }
        guard let lastAutomaticCheckAt else { return true }
        let elapsed = now.timeIntervalSince(lastAutomaticCheckAt)
        guard elapsed >= 0 else { return false }
        return elapsed >= settings.automaticCheckInterval.duration
    }
}
