import MediaPlayer

@MainActor
final class AppleReaderRemoteCommandManager: ReaderRemoteCommandManaging {
    var commandHandler: ((ReaderRemoteCommand) -> Bool)?

    private let center: MPRemoteCommandCenter
    private var registrations: [(MPRemoteCommand, Any)] = []

    init(center: MPRemoteCommandCenter = .shared()) {
        self.center = center
        register(center.playCommand, command: .play)
        register(center.pauseCommand, command: .pause)
        register(center.togglePlayPauseCommand, command: .togglePlayPause)
        register(center.nextTrackCommand, command: .next)
        register(center.previousTrackCommand, command: .previous)
    }

    func updateNowPlaying(bookTitle: String, chapterTitle: String, isPlaying: Bool) {
        MPNowPlayingInfoCenter.default().nowPlayingInfo = [
            MPMediaItemPropertyTitle: chapterTitle,
            MPMediaItemPropertyAlbumTitle: bookTitle,
            MPNowPlayingInfoPropertyMediaType: MPNowPlayingInfoMediaType.audio.rawValue
        ]
        MPNowPlayingInfoCenter.default().playbackState = isPlaying ? .playing : .paused
    }

    func clearNowPlaying() {
        MPNowPlayingInfoCenter.default().playbackState = .stopped
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
    }

    private func register(_ remoteCommand: MPRemoteCommand, command: ReaderRemoteCommand) {
        remoteCommand.isEnabled = true
        let token = remoteCommand.addTarget { [weak self] _ in
            guard let self else { return .commandFailed }
            Task { @MainActor [weak self] in
                _ = self?.commandHandler?(command)
            }
            return .success
        }
        registrations.append((remoteCommand, token))
    }
}
