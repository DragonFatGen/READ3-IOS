import Foundation
@preconcurrency import UserNotifications

enum LibraryNotificationAuthorizationStatus: Equatable {
    case notDetermined
    case denied
    case authorized
}

struct LibraryBookUpdateNotification: Equatable, Sendable {
    let bookID: String
    let bookName: String
    let newChapterCount: Int
    let latestChapterName: String?
}

struct LibraryUpdateNotificationContent: Equatable, Sendable {
    let identifier: String
    let title: String
    let body: String
    let bookID: String?
}

enum LibraryUpdateNotificationBuilder {
    static func make(
        updates: [LibraryBookUpdateNotification]
    ) -> LibraryUpdateNotificationContent? {
        let updates = updates.filter { $0.newChapterCount > 0 }
        guard !updates.isEmpty else { return nil }
        if updates.count == 1, let update = updates.first {
            return LibraryUpdateNotificationContent(
                identifier: "library-update-\(update.bookID)",
                title: "《\(update.bookName)》更新了 \(update.newChapterCount) 章",
                body: update.latestChapterName.map { "最新：\($0)" } ?? "发现新章节",
                bookID: update.bookID
            )
        }
        let chapterCount = updates.reduce(0) { $0 + $1.newChapterCount }
        return LibraryUpdateNotificationContent(
            identifier: "library-update-summary",
            title: "\(updates.count) 本书有新章节",
            body: "共更新 \(chapterCount) 章",
            bookID: nil
        )
    }
}

@MainActor
protocol LibraryUpdateNotifying: AnyObject {
    func authorizationStatus() async -> LibraryNotificationAuthorizationStatus
    func requestAuthorization() async -> Bool
    func notify(updates: [LibraryBookUpdateNotification]) async
}

@MainActor
final class UserNotificationLibraryUpdateNotifier: LibraryUpdateNotifying {
    private let center: UNUserNotificationCenter

    init(center: UNUserNotificationCenter = .current()) {
        self.center = center
    }

    func authorizationStatus() async -> LibraryNotificationAuthorizationStatus {
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            return LibraryNotificationAuthorizationStatus.authorized
        case .denied:
            return LibraryNotificationAuthorizationStatus.denied
        case .notDetermined:
            return LibraryNotificationAuthorizationStatus.notDetermined
        @unknown default:
            return LibraryNotificationAuthorizationStatus.denied
        }
    }

    func requestAuthorization() async -> Bool {
        (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
    }

    func notify(updates: [LibraryBookUpdateNotification]) async {
        guard let payload = LibraryUpdateNotificationBuilder.make(updates: updates),
              await authorizationStatus() == .authorized else { return }
        let content = UNMutableNotificationContent()
        content.sound = .default
        content.title = payload.title
        content.body = payload.body
        if let bookID = payload.bookID { content.userInfo = ["bookID": bookID] }
        let request = UNNotificationRequest(
            identifier: payload.identifier,
            content: content,
            trigger: nil
        )
        try? await center.add(request)
    }
}
