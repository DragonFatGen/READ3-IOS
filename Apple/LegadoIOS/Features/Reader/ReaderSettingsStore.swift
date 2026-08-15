import Combine
import Foundation

@MainActor
final class ReaderSettingsStore: ObservableObject {
    @Published private(set) var settings: ReaderSettings { didSet { persist() } }

    private let defaults: UserDefaults
    private let keyPrefix: String

    init(defaults: UserDefaults = .standard, keyPrefix: String = "reader.settings") {
        self.defaults = defaults
        self.keyPrefix = keyPrefix
        let fallback = ReaderSettings.default
        settings = ReaderSettings(
            fontSize: defaults.object(forKey: "\(keyPrefix).fontSize") == nil
                ? fallback.fontSize : defaults.double(forKey: "\(keyPrefix).fontSize"),
            lineSpacing: defaults.object(forKey: "\(keyPrefix).lineSpacing") == nil
                ? fallback.lineSpacing : defaults.double(forKey: "\(keyPrefix).lineSpacing"),
            horizontalPadding: defaults.object(forKey: "\(keyPrefix).horizontalPadding") == nil
                ? fallback.horizontalPadding : defaults.double(forKey: "\(keyPrefix).horizontalPadding"),
            theme: defaults.string(forKey: "\(keyPrefix).theme").flatMap(ReaderTheme.init(rawValue:))
                ?? fallback.theme,
            layoutMode: defaults.string(forKey: "\(keyPrefix).layoutMode")
                .flatMap(ReaderLayoutMode.init(rawValue:)) ?? fallback.layoutMode
        ).clamped()
    }

    func adjustFontSize(by amount: Double) {
        settings.fontSize += amount
        settings = settings.clamped()
    }

    func adjustLineSpacing(by amount: Double) {
        settings.lineSpacing += amount
        settings = settings.clamped()
    }

    func adjustHorizontalPadding(by amount: Double) {
        settings.horizontalPadding += amount
        settings = settings.clamped()
    }

    func selectTheme(_ theme: ReaderTheme) { settings.theme = theme }

    func selectLayoutMode(_ mode: ReaderLayoutMode) { settings.layoutMode = mode }

    private func persist() {
        let value = settings.clamped()
        defaults.set(value.fontSize, forKey: "\(keyPrefix).fontSize")
        defaults.set(value.lineSpacing, forKey: "\(keyPrefix).lineSpacing")
        defaults.set(value.horizontalPadding, forKey: "\(keyPrefix).horizontalPadding")
        defaults.set(value.theme.rawValue, forKey: "\(keyPrefix).theme")
        defaults.set(value.layoutMode.rawValue, forKey: "\(keyPrefix).layoutMode")
    }
}
