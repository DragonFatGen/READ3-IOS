@preconcurrency import AVFoundation
import Foundation

@MainActor
final class AppleReaderAudioSessionManager: NSObject, ReaderAudioSessionManaging {
    var eventHandler: ((ReaderAudioSessionEvent) -> Void)?

    private let session: AVAudioSession

    init(session: AVAudioSession = .sharedInstance()) {
        self.session = session
        super.init()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleInterruption(_:)),
            name: AVAudioSession.interruptionNotification,
            object: session
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleRouteChange(_:)),
            name: AVAudioSession.routeChangeNotification,
            object: session
        )
    }

    deinit { NotificationCenter.default.removeObserver(self) }

    func activate() throws {
        try session.setCategory(.playback, mode: .spokenAudio, options: [])
        try session.setActive(true)
    }

    func deactivate() {
        try? session.setActive(false, options: .notifyOthersOnDeactivation)
    }

    @objc nonisolated private func handleInterruption(_ notification: Notification) {
        guard let rawValue = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
              AVAudioSession.InterruptionType(rawValue: rawValue) == .began else { return }
        Task { @MainActor [weak self] in self?.eventHandler?(.interruptionBegan) }
    }

    @objc nonisolated private func handleRouteChange(_ notification: Notification) {
        guard let rawValue = notification.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt,
              AVAudioSession.RouteChangeReason(rawValue: rawValue) == .oldDeviceUnavailable else {
            return
        }
        Task { @MainActor [weak self] in self?.eventHandler?(.headphonesRemoved) }
    }
}
