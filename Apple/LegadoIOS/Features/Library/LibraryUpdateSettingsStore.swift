import Combine
import Foundation

@MainActor
final class LibraryUpdateSettingsStore: ObservableObject {
    @Published private(set) var settings: LibraryUpdateSettings
    @Published private(set) var notificationPermissionMessage: String?

    private let defaults: UserDefaults
    private let keyPrefix: String

    init(defaults: UserDefaults = .standard, keyPrefix: String = "library.update.settings") {
        self.defaults = defaults
        self.keyPrefix = keyPrefix
        let fallback = LibraryUpdateSettings.default
        settings = LibraryUpdateSettings(
            automaticCheckEnabled: defaults.object(forKey: "\(keyPrefix).automaticEnabled") == nil
                ? fallback.automaticCheckEnabled
                : defaults.bool(forKey: "\(keyPrefix).automaticEnabled"),
            automaticCheckInterval: defaults.string(forKey: "\(keyPrefix).interval")
                .flatMap(LibraryUpdateInterval.init(rawValue:)) ?? fallback.automaticCheckInterval,
            notificationEnabled: defaults.object(forKey: "\(keyPrefix).notificationEnabled") == nil
                ? fallback.notificationEnabled
                : defaults.bool(forKey: "\(keyPrefix).notificationEnabled")
        )
    }

    var lastAutomaticCheckAt: Date? {
        get { defaults.object(forKey: "\(keyPrefix).lastAutomaticCheckAt") as? Date }
        set { defaults.set(newValue, forKey: "\(keyPrefix).lastAutomaticCheckAt") }
    }

    func setAutomaticCheckEnabled(_ enabled: Bool) {
        settings.automaticCheckEnabled = enabled
        persist()
    }

    func setInterval(_ interval: LibraryUpdateInterval) {
        settings.automaticCheckInterval = interval
        persist()
    }

    func setNotificationEnabled(
        _ enabled: Bool,
        notifier: any LibraryUpdateNotifying
    ) async {
        notificationPermissionMessage = nil
        guard enabled else {
            settings.notificationEnabled = false
            persist()
            return
        }
        let status = await notifier.authorizationStatus()
        let granted: Bool
        switch status {
        case .authorized: granted = true
        case .notDetermined: granted = await notifier.requestAuthorization()
        case .denied: granted = false
        }
        settings.notificationEnabled = granted
        notificationPermissionMessage = granted ? nil : "通知权限未开启"
        persist()
    }

    func synchronizeNotificationAuthorization(using notifier: any LibraryUpdateNotifying) async {
        guard settings.notificationEnabled else { return }
        if await notifier.authorizationStatus() != .authorized {
            settings.notificationEnabled = false
            notificationPermissionMessage = "通知权限未开启"
            persist()
        }
    }

    private func persist() {
        defaults.set(settings.automaticCheckEnabled, forKey: "\(keyPrefix).automaticEnabled")
        defaults.set(settings.automaticCheckInterval.rawValue, forKey: "\(keyPrefix).interval")
        defaults.set(settings.notificationEnabled, forKey: "\(keyPrefix).notificationEnabled")
    }
}
