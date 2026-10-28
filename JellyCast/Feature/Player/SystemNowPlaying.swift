import AetherEngine
import MediaPlayer
import UIKit

/// The lock screen, Control Center and Dynamic Island card for what plays in the app, and the
/// commands from there and from headphones. iOS also keeps an app that publishes this as the
/// active player when the screen locks.
final class SystemNowPlaying {
    private weak var engine: AetherEngine?
    private var identity: [String: Any] = [:]
    private var shownItemID: String?
    private var commandTargets: [(MPRemoteCommand, Any)] = []

    private static let skipSeconds = 10.0
    private static let artworkPixelWidth = 640

    func show(_ playable: Playable, engine: AetherEngine, client: JellyfinClient) async {
        self.engine = engine
        if commandTargets.isEmpty { registerCommands() }
        guard shownItemID != playable.id else { return }
        shownItemID = playable.id
        identity = Self.identity(of: playable)
        update()
        guard let artwork = await Self.artwork(of: playable, client: client), shownItemID == playable.id
        else { return }
        identity[MPMediaItemPropertyArtwork] = artwork
        update()
    }

    /// Time and rate; iOS runs the clock on from these until the next update.
    func update() {
        guard let engine, shownItemID != nil else { return }
        var info = identity
        info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = engine.currentTime
        info[MPNowPlayingInfoPropertyPlaybackRate] = engine.state == .playing ? 1.0 : 0.0
        info[MPNowPlayingInfoPropertyDefaultPlaybackRate] = 1.0
        if engine.duration > 0 { info[MPMediaItemPropertyPlaybackDuration] = engine.duration }
        let center = MPNowPlayingInfoCenter.default()
        center.nowPlayingInfo = info
        center.playbackState = engine.state == .playing ? .playing : .paused
    }

    func clear() {
        shownItemID = nil
        identity = [:]
        for (command, target) in commandTargets { command.removeTarget(target) }
        commandTargets = []
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
        MPNowPlayingInfoCenter.default().playbackState = .stopped
    }

    private func registerCommands() {
        let center = MPRemoteCommandCenter.shared()
        add(center.playCommand) { $0.play() }
        add(center.pauseCommand) { $0.pause() }
        add(center.togglePlayPauseCommand) { $0.togglePlayPause() }
        center.skipForwardCommand.preferredIntervals = [NSNumber(value: Self.skipSeconds)]
        center.skipBackwardCommand.preferredIntervals = [NSNumber(value: Self.skipSeconds)]
        add(center.skipForwardCommand) { engine in
            Task { await engine.seek(to: engine.currentTime + Self.skipSeconds) }
        }
        add(center.skipBackwardCommand) { engine in
            Task { await engine.seek(to: max(0, engine.currentTime - Self.skipSeconds)) }
        }
        let position = center.changePlaybackPositionCommand
        position.isEnabled = true
        let target = position.addTarget { [weak self] event in
            guard let engine = self?.engine, let event = event as? MPChangePlaybackPositionCommandEvent
            else { return .commandFailed }
            Task { await engine.seek(to: event.positionTime) }
            return .success
        }
        commandTargets.append((position, target))
    }

    private func add(_ command: MPRemoteCommand, _ action: @escaping (AetherEngine) -> Void) {
        command.isEnabled = true
        let target = command.addTarget { [weak self] _ in
            guard let engine = self?.engine else { return .noActionableNowPlayingItem }
            action(engine)
            return .success
        }
        commandTargets.append((command, target))
    }

    private static func identity(of playable: Playable) -> [String: Any] {
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: playable.name,
            MPNowPlayingInfoPropertyMediaType: MPNowPlayingInfoMediaType.video.rawValue,
        ]
        switch playable {
        case .movie(let movie):
            if let year = movie.year { info[MPMediaItemPropertyArtist] = String(year) }
        case .episode(let episode):
            info[MPMediaItemPropertyArtist] = Format.joined([
                episode.seriesName, Format.seasonEpisode(episode),
            ])
        }
        return info
    }

    private static func artwork(of playable: Playable, client: JellyfinClient) async -> MPMediaItemArtwork? {
        let source: (ImageRef, JellyfinClient.ImageType)?
        switch playable {
        case .movie(let movie):
            source = movie.backdrop.map { ($0, .backdrop) } ?? movie.poster.map { ($0, .primary) }
        case .episode(let episode):
            source = episode.still.map { ($0, .primary) }
                ?? episode.seriesBackdrop.map { ($0, .backdrop) }
                ?? episode.seriesPoster.map { ($0, .primary) }
        }
        guard let (ref, type) = source else { return nil }
        let url = client.imageURL(ref, type: type, pixelWidth: artworkPixelWidth)
        guard let image = await ImagePipeline.shared.image(for: url) else { return nil }
        return Self.artwork(image)
    }

    /// MediaPlayer calls the handler off the main thread.
    nonisolated private static func artwork(_ image: UIImage) -> MPMediaItemArtwork {
        MPMediaItemArtwork(boundsSize: image.size) { _ in image }
    }
}
