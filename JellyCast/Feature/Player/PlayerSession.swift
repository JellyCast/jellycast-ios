import AVFoundation
import AetherEngine
import Foundation
import OSLog

/// One play of one item: loads it, reports it, and knows its segments and what plays next.
@Observable
final class PlayerSession {
    enum StartPhase: Equatable {
        case preparing
        /// The connection is slower than the file's peaks; loading ahead before the start.
        case loadingAhead(secondsLeft: Int, connectionMbps: Int, peakMbps: Int)
        case started
    }

    private(set) var playable: Playable
    private(set) var segments: [MediaSegment] = []
    private(set) var loadError: String?
    private(set) var startPhase = StartPhase.preparing
    private(set) var mediaInfo: MediaInfo?
    /// What plays now; chosen once at the start and kept until the user changes it.
    private(set) var level: StreamLevel?
    /// The quality picked in the player; it holds for the rest of this play, next episodes included.
    private(set) var chosenPreference: QualityPreference?
    /// The audio track asked of a transcode, which carries only that one track.
    private(set) var transcodeAudioIndex: Int?
    /// The subtitle track asked of a transcode; the server sends only that one.
    private(set) var transcodeSubtitleIndex: Int?
    /// The tracks another device played; applied once, at the next start.
    var requestedStreams: StreamSelection?
    /// The list this item plays from; its next item comes in place of the next episode.
    private(set) var queue: PlayQueue?
    let buffer = BufferWatch()
    /// The connection speed Auto chose by, kept up to date while the original file streams.
    private(set) var connectionBitsPerSecond: Double?

    let engine: AetherEngine
    private let store: LibraryStore
    private var report: PlaybackReport?
    /// Set while a download plays: its position is kept on the device instead of reported.
    private var playsDownload = false
    private var progressTask: Task<Void, Never>?
    private var lastReportedPause = false
    private var cache: StreamCache?
    private var startNowRequested = false
    private var bufferWatchTask: Task<Void, Never>?
    /// Where a play that failed halfway was, so "Try again" goes on from there.
    private var failedAtSeconds: Double?

    private static let logger = Logger(subsystem: "nl.jellycast.ios", category: "player")
    private static let progressInterval = Duration.seconds(10)
    /// Without an Outro segment, stopping this close to the end counts as watched.
    private static let creditsFallbackSeconds = 30.0
    private static let leadMarginSeconds = 30.0
    private static let aheadWhilePlayingSeconds = 5 * 60.0
    private static let maxAheadBytes: Int64 = 1536 * 1024 * 1024
    private static let countdownInterval = Duration.milliseconds(500)
    private static let measureChunks = 3
    private static let subtitleWaitStep = Duration.milliseconds(100)
    private static let subtitleWaitSteps = 30
    private static let bufferWatchInterval = Duration.seconds(1)
    /// The buffer reaching this close to the end of the file can only run down.
    private static let endMarginSeconds = 10.0

    init(playable: Playable, engine: AetherEngine, store: LibraryStore) {
        self.playable = playable
        self.engine = engine
        self.store = store
    }

    /// The next item of the list, or else the next episode.
    var nextItem: Playable? {
        if let queue { return queue.next.map(current) }
        return nextEpisode.map(Playable.episode)
    }

    /// Keeps the list when the item is part of it, as when an item in the list is tapped.
    func follow(_ playable: Playable, queue newQueue: PlayQueue?) {
        if let newQueue {
            queue = newQueue
        } else if queue?.moveTo(playable) != true {
            queue = nil
        }
    }

    /// The queue holds the item as it was when the list started; the index has its position since.
    private func current(_ playable: Playable) -> Playable {
        store.index?.playable(id: playable.id) ?? playable
    }

    private var nextEpisode: Episode? {
        guard case .episode(let episode) = playable,
              let episodes = store.index?.progress(of: episode.seriesID)?.episodes,
              let position = episodes.firstIndex(where: { $0.id == episode.id })
        else { return nil }
        return episodes[(position + 1)...].first { ($0.seasonNumber ?? 0) > 0 }
    }

    var isTranscoding: Bool { level.map { $0 != .original } ?? false }

    /// The quality that applies now: the one picked in the player, else the setting for this network.
    var activePreference: QualityPreference {
        chosenPreference ?? networkPreference
    }

    var networkPreference: QualityPreference {
        let network = NetworkMonitor.shared.kind(serverURL: store.session.client.serverURL)
        return QualitySettings.shared.preference(for: network)
    }

    var offeredLevels: [StreamLevel] {
        mediaInfo.map { QualityChoice.offered(for: $0.sourceVideo) } ?? []
    }

    func skippableSegment(at seconds: Double) -> MediaSegment? {
        MediaSegment.skippable(in: segments, at: seconds)
    }

    func isInCredits(at seconds: Double) -> Bool {
        if let outro = segments.first(where: { $0.kind == .outro }) { return seconds >= outro.startSeconds }
        return engine.duration > 0 && engine.duration - seconds <= Self.creditsFallbackSeconds
    }

    func load() async {
        if let failedAtSeconds {
            self.failedAtSeconds = nil
            await load(startSeconds: failedAtSeconds)
            return
        }
        let startTicks = playable.watch.isInProgress ? playable.watch.positionTicks : 0
        await load(startSeconds: Ticks.seconds(startTicks))
    }

    private func load(startSeconds: Double) async {
        loadError = nil
        startPhase = .preparing
        startNowRequested = false
        buffer.stop()
        let session = store.session
        let itemID = playable.id
        if let file = DownloadStore.localFile(itemID: itemID) {
            await loadDownloaded(file, startSeconds: startSeconds)
            return
        }
        do {
            async let segmentsRequest = try? session.client.mediaSegments(itemID: itemID)
            async let originalLanguages = OriginalLanguages.shared.languages(
                itemID: itemID, client: session.client, userID: session.userID
            )
            guard let info = try await session.client.mediaInfo(itemID: itemID, userID: session.userID) else {
                loadError = String(localized: "This item has no file the server can play.")
                return
            }
            mediaInfo = info
            let languages = await originalLanguages + AudioLanguage.fallback
            let requested = requestedStreams
            requestedStreams = nil
            if let audio = requested?.audio, info.audioStreams.contains(where: { $0.Index == audio }) {
                transcodeAudioIndex = audio
            }
            if let subtitle = requested?.subtitle, info.subtitleStreams.contains(where: { $0.Index == subtitle }) {
                transcodeSubtitleIndex = subtitle
            }
            if transcodeAudioIndex == nil {
                transcodeAudioIndex = Self.preferredAudioStream(in: info, languages: languages)
            }
            let stream = try await prepareStream(itemID: itemID, info: info, startSeconds: startSeconds)
            try await engine.load(
                url: stream.url,
                startPosition: startSeconds > 0 ? startSeconds : nil,
                options: LoadOptions(httpHeaders: ["Authorization": session.client.authorizationHeader])
            )
            if !stream.isTranscode {
                if !selectRequestedTracks(requested, info: info) { selectPreferredAudioTrack(languages: languages) }
            }
            if stream.isTranscode, transcodeSubtitleIndex != nil {
                Task { await showServerSubtitle() }
            }
            startPhase = .started
            segments = await segmentsRequest ?? []
            engine.play()
            let started = PlaybackReport(
                itemID: itemID, mediaSourceID: info.mediaSourceID, playSessionID: stream.playSessionID,
                positionTicks: Self.ticks(startSeconds), isPaused: false,
                audioStreamIndex: stream.isTranscode ? transcodeAudioIndex : nil, isTranscode: stream.isTranscode
            )
            report = started
            store.reporter.start(started)
            startProgressReports()
            startBufferWatch()
        } catch is CancellationError {
            return
        } catch {
            loadError = Self.message(for: error)
        }
    }

    /// Plays the file on the device with no server call, so it works offline.
    private func loadDownloaded(_ file: URL, startSeconds: Double) async {
        Self.logger.info("Playing the download \(file.lastPathComponent, privacy: .public)")
        do {
            try await engine.load(url: file, startPosition: startSeconds > 0 ? startSeconds : nil)
            startPhase = .started
            engine.play()
            playsDownload = true
            startProgressReports()
        } catch is CancellationError {
            return
        } catch {
            Self.logger.error("Download did not play: \(error.localizedDescription, privacy: .public)")
            loadError = Self.message(for: error)
        }
    }

    private static func preferredAudioStream(in info: MediaInfo, languages: [String]) -> Int? {
        let tracks = info.audioStreams.compactMap { stream in
            stream.Index.map { index in
                AudioLanguage.Track(
                    id: index, language: stream.Language, isDefault: stream.IsDefault == true,
                    isCommentary: stream.DisplayTitle?.localizedCaseInsensitiveContains("comment") == true
                )
            }
        }
        return AudioLanguage.preferredTrack(in: tracks, languages: languages)?.id
    }

    /// The tracks that play now as the server's stream indexes, for a TV that takes over.
    var currentStreams: StreamSelection? {
        guard let info = mediaInfo else { return nil }
        if isTranscoding {
            return StreamSelection(
                audio: transcodeAudioIndex, subtitle: transcodeSubtitleIndex ?? RemoteCommand.subtitlesOff
            )
        }
        let audio = engine.activeAudioTrackIndex.flatMap {
            StreamSelection.serverIndex(
                forPlayer: $0, server: Self.embedded(info.audioStreams), player: engine.audioTracks.embeddedIDs
            )
        }
        let subtitle = engine.activeSubtitleTrackIndex.flatMap {
            StreamSelection.serverIndex(
                forPlayer: $0, server: Self.embedded(info.subtitleStreams), player: engine.subtitleTracks.embeddedIDs
            )
        }
        return StreamSelection(audio: audio, subtitle: subtitle ?? RemoteCommand.subtitlesOff)
    }

    /// Returns whether an audio track was requested and found; then the language choice is skipped.
    private func selectRequestedTracks(_ requested: StreamSelection?, info: MediaInfo) -> Bool {
        guard let requested else { return false }
        if let subtitle = requested.subtitle,
           let track = StreamSelection.playerTrack(
               forServer: subtitle, server: Self.embedded(info.subtitleStreams), player: engine.subtitleTracks.embeddedIDs
           ) {
            engine.selectSubtitleTrack(index: track)
        }
        guard let audio = requested.audio,
              let track = StreamSelection.playerTrack(
                  forServer: audio, server: Self.embedded(info.audioStreams), player: engine.audioTracks.embeddedIDs
              )
        else { return false }
        if track != engine.activeAudioTrackIndex { engine.selectAudioTrack(index: track) }
        return true
    }

    private static func embedded(_ streams: [MediaInfo.Stream]) -> [Int] {
        streams.filter { $0.IsExternal != true }.compactMap(\.Index)
    }

    /// The engine starts on the file's default track, which in a dubbed release is the dub.
    private func selectPreferredAudioTrack(languages: [String]) {
        let tracks = engine.audioTracks.map {
            AudioLanguage.Track(
                id: $0.id, language: $0.language, isDefault: $0.isDefault, isCommentary: $0.isCommentary
            )
        }
        guard let track = AudioLanguage.preferredTrack(in: tracks, languages: languages),
              track.id != engine.activeAudioTrackIndex
        else { return }
        Self.logger.info("Audio track \(track.id) (\(track.language ?? "?", privacy: .public)) instead of the default")
        engine.selectAudioTrack(index: track.id)
    }

    /// The reason in words for the user; the engine's own text is technical and stays in the log.
    private static func message(for error: Error) -> String {
        switch error {
        case let jellyfin as JellyfinError: jellyfin.localizedDescription
        case let url as URLError: JellyfinError.unreachable(url).localizedDescription
        default: String(localized: "This file doesn't play on this iPhone.")
        }
    }

    /// The best transcode for this file, offered when the original does not play.
    var serverTranscodeLevel: StreamLevel? {
        guard !isTranscoding else { return nil }
        return offeredLevels.first { $0 != .original }
    }

    /// Plays the item as a server transcode, for a file the iPhone can't play itself.
    func playThroughServer() async {
        guard let level = serverTranscodeLevel else { return }
        chosenPreference = .fixed(level)
        await load()
    }

    func startNow() {
        startNowRequested = true
    }

    /// Plays on at the current position in another quality, picked in the player.
    func changeQuality(to preference: QualityPreference) async {
        chosenPreference = preference
        await reload()
    }

    /// A transcode carries one audio track, so another track means a new transcode.
    func selectTranscodeAudio(streamIndex: Int) async {
        transcodeAudioIndex = streamIndex
        await reload()
    }

    /// Like audio, a transcode carries at most the one subtitle track asked for.
    func selectTranscodeSubtitle(streamIndex: Int?) async {
        transcodeSubtitleIndex = streamIndex
        await reload()
    }

    private func reload() async {
        let seconds = engine.clock.currentTime
        stop()
        await load(startSeconds: seconds)
    }

    /// The server's subtitle rendition surfaces shortly after the load, and AVPlayer leaves it off.
    private func showServerSubtitle() async {
        for _ in 0..<Self.subtitleWaitSteps {
            if let rendition = engine.subtitleTracks.first {
                engine.selectSubtitleTrack(index: rendition.id)
                return
            }
            try? await Task.sleep(for: Self.subtitleWaitStep)
        }
    }

    private struct PreparedStream {
        let url: URL
        let playSessionID: String
        var isTranscode = false
    }

    private func prepareStream(itemID: String, info: MediaInfo, startSeconds: Double) async throws -> PreparedStream {
        let preference = activePreference
        var connection: Double?
        if preference.isAuto {
            connection = await connectionBytesPerSecond(itemID: itemID, info: info, startSeconds: startSeconds)
            connectionBitsPerSecond = connection.map { $0 * 8 }
        }
        let chosen = QualityChoice.level(
            for: preference, source: info.sourceVideo, connectionBitsPerSecond: connection.map { $0 * 8 }
        )
        level = chosen
        guard let maxWidth = chosen.maxWidth, let maxBits = chosen.maxBitsPerSecond else {
            let url = try await prepareOriginal(itemID: itemID, info: info, startSeconds: startSeconds)
            return PreparedStream(url: url, playSessionID: UUID().uuidString)
        }
        StreamCaches.shared.release(itemID: itemID)
        let session = store.session
        let transcode = try await session.client.transcodeStream(
            itemID: itemID, mediaSourceID: info.mediaSourceID, userID: session.userID,
            maxWidth: maxWidth, maxBitsPerSecond: maxBits,
            audioStreamIndex: transcodeAudioIndex, subtitleStreamIndex: transcodeSubtitleIndex
        )
        return PreparedStream(url: transcode.url, playSessionID: transcode.playSessionID, isTranscode: true)
    }

    /// The fresh measurement from the warm-up, or one taken now from the chunks at the start position.
    private func connectionBytesPerSecond(itemID: String, info: MediaInfo, startSeconds: Double) async -> Double? {
        if let fresh = ConnectionMeter.shared.freshBytesPerSecond { return fresh }
        guard let cache = try? await openCache(itemID: itemID, info: info) else { return nil }
        let first = cache.chunk(containing: startOffset(in: cache, info: info, startSeconds: startSeconds))
        for chunk in first..<min(cache.chunkCount, first + Self.measureChunks) {
            _ = try? await cache.data(chunk: chunk)
        }
        return ConnectionMeter.shared.freshBytesPerSecond
    }

    private func openCache(itemID: String, info: MediaInfo) async throws -> StreamCache {
        try await StreamCaches.shared.cache(
            itemID: itemID, mediaSourceID: info.mediaSourceID, bitsPerSecond: info.bitsPerSecond,
            session: store.session
        )
    }

    private func startOffset(in cache: StreamCache, info: MediaInfo, startSeconds: Double) -> Int64 {
        let bytesPerSecond = Double(max(info.bitsPerSecond, 1)) / 8
        return min(Int64(startSeconds * bytesPerSecond), max(0, cache.totalBytes - 1))
    }

    /// Routes the file through the local cache and, when the connection can't keep up with the
    /// file's peaks, loads ahead first. Falls back to the server URL when the cache can't open.
    private func prepareOriginal(itemID: String, info: MediaInfo, startSeconds: Double) async throws -> URL {
        let session = store.session
        let bytesPerSecond = Double(max(info.bitsPerSecond, 1)) / 8
        guard let cache = try? await openCache(itemID: itemID, info: info),
              let localURL = try? await LocalStreamServer.shared.url(for: cache)
        else {
            return session.client.originalStreamURL(itemID: itemID, mediaSourceID: info.mediaSourceID)
        }
        self.cache = cache
        let startOffset = startOffset(in: cache, info: info, startSeconds: startSeconds)
        let playingAhead = min(Int64(Self.aheadWhilePlayingSeconds * bytesPerSecond), Self.maxAheadBytes)
        await cache.startPrefetch(from: startOffset, aheadBytes: playingAhead)

        guard info.bitsPerSecond > 0, let connection = await measuredThroughput(cache, from: startOffset) else {
            return localURL
        }
        let peak = bytesPerSecond * QualityChoice.headroom
        guard connection < peak else { return localURL }

        let remainingSeconds = max(0, Ticks.seconds(playable.runtimeTicks ?? 0) - startSeconds)
        let leadSeconds = remainingSeconds * (1 - connection / peak) + Self.leadMarginSeconds
        let neededBytes = min(
            Int64(leadSeconds * bytesPerSecond), cache.totalBytes - startOffset, Self.maxAheadBytes
        )
        await cache.startPrefetch(from: startOffset, aheadBytes: max(neededBytes, playingAhead))
        while !startNowRequested, !Task.isCancelled {
            let present = await cache.contiguousBytes(from: startOffset)
            guard present < neededBytes else { break }
            let current = await cache.bytesPerSecond ?? connection
            startPhase = .loadingAhead(
                secondsLeft: Int(Double(neededBytes - present) / max(current, 1)),
                connectionMbps: Int(current * 8 / 1_000_000),
                peakMbps: Int(peak * 8 / 1_000_000)
            )
            try await Task.sleep(for: Self.countdownInterval)
        }
        return localURL
    }

    /// The connection speed from the warm-up, or from fetching the chunks at the start position.
    private func measuredThroughput(_ cache: StreamCache, from offset: Int64) async -> Double? {
        if let measured = await cache.bytesPerSecond { return measured }
        let first = cache.chunk(containing: offset)
        for chunk in first..<min(cache.chunkCount, first + Self.measureChunks) {
            _ = try? await cache.data(chunk: chunk)
        }
        return await cache.bytesPerSecond
    }

    /// Reports a pause or resume as soon as it happens, not at the next interval.
    func stateChanged(_ state: PlaybackState) {
        if case .error(let message) = state, startPhase == .started {
            Self.logger.error("Playback failed: \(message, privacy: .public)")
            let seconds = engine.clock.currentTime
            stop()
            failedAtSeconds = seconds > 0 ? seconds : nil
            loadError = String(
                localized: "Playback stopped because of an error in the file or the connection."
            )
            return
        }
        let paused = state == .paused
        guard report != nil || playsDownload, paused != lastReportedPause, state == .paused || state == .playing else { return }
        lastReportedPause = paused
        reportProgress(event: paused ? "Pause" : "Unpause")
    }

    func seeked() {
        buffer.seeked()
        reportProgress(event: "TimeUpdate")
    }

    func bufferingChanged(_ isBuffering: Bool) {
        buffer.bufferingChanged(isBuffering && startPhase == .started)
    }

    private func startBufferWatch() {
        bufferWatchTask?.cancel()
        bufferWatchTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.updateBufferedAhead()
                try? await Task.sleep(for: Self.bufferWatchInterval)
            }
        }
    }

    /// What the engine holds ahead, plus, for the original file, what the local cache holds after
    /// the engine's read position.
    private func updateBufferedAhead() async {
        let position = engine.clock.currentTime
        let engineAhead = isTranscoding
            ? Self.playerAheadSeconds(engine.currentAVPlayer?.currentItem)
            : max(0, engine.bufferedPosition - position)
        var cacheAhead = 0.0
        if let cache, cache.bitsPerSecond > 0 {
            cacheAhead = Double(await cache.bytesAheadOfRead()) * 8 / Double(cache.bitsPerSecond)
            if let measured = await cache.bytesPerSecond { connectionBitsPerSecond = measured * 8 }
        }
        let ahead = engineAhead + cacheAhead
        buffer.record(
            aheadSeconds: ahead,
            isPlaying: engine.state == .playing && !engine.isSeeking,
            reachesEnd: engine.duration > 0 && position + ahead >= engine.duration - Self.endMarginSeconds
        ) { [weak self] in
            guard let self, let level = self.level else { return nil }
            return self.offeredLevels.first { $0 < level }
        }
    }

    /// The engine reports no buffer on its remote HLS route (a transcode); AVPlayer's loaded
    /// range around the play position is the buffer there.
    private static func playerAheadSeconds(_ item: AVPlayerItem?) -> Double {
        guard let item else { return 0 }
        let now = item.currentTime()
        let range = item.loadedTimeRanges.map(\.timeRangeValue).first { $0.containsTime(now) }
        guard let range else { return 0 }
        let ahead = (range.end - now).seconds
        return ahead.isFinite ? max(0, ahead) : 0
    }

    /// Ends this play: reports the stop, records it locally and syncs once the reports are sent.
    /// The stop report carries the transcode's play session id, which makes the server end it.
    func stop() {
        progressTask?.cancel()
        bufferWatchTask?.cancel()
        buffer.stop()
        startNowRequested = true
        if let cache {
            Task { await cache.stopPrefetch() }
            StreamCaches.shared.release(itemID: cache.itemID)
            self.cache = nil
        }
        if playsDownload {
            stopDownload()
            return
        }
        guard var current = report else { return }
        report = nil
        let seconds = engine.clock.currentTime
        let finished = engine.state == .ended || isInCredits(at: seconds)
        current.positionTicks = Self.ticks(seconds)
        store.reporter.stop(current, finished: finished)
        store.recordPlayback(itemID: current.itemID, positionTicks: current.positionTicks, finished: finished)
        let store = store
        Task {
            await store.reporter.flush()
            await store.refresh()
        }
    }

    /// The position goes to the device first; the server gets it now when it answers, else later.
    private func stopDownload() {
        playsDownload = false
        let seconds = engine.clock.currentTime
        let finished = engine.state == .ended || isInCredits(at: seconds)
        let ticks = Self.ticks(seconds)
        OfflineProgress.shared.record(itemID: playable.id, positionTicks: ticks, finished: finished)
        store.recordPlayback(itemID: playable.id, positionTicks: ticks, finished: finished)
        let store = store
        Task { await store.sendOfflineProgress() }
    }

    func playNext() async {
        guard let next = nextItem else { return }
        queue?.advance()
        await play(next)
    }

    func play(_ next: Playable, streams: StreamSelection? = nil) async {
        stop()
        playable = next
        requestedStreams = streams
        segments = []
        mediaInfo = nil
        level = nil
        transcodeAudioIndex = nil
        transcodeSubtitleIndex = nil
        failedAtSeconds = nil
        await load()
    }

    private func startProgressReports() {
        progressTask?.cancel()
        progressTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: Self.progressInterval)
                guard !Task.isCancelled else { return }
                self?.reportProgress(event: "TimeUpdate")
            }
        }
    }

    private func reportProgress(event: String) {
        if playsDownload {
            let ticks = Self.ticks(engine.clock.currentTime)
            guard ticks > 0 else { return }
            OfflineProgress.shared.record(itemID: playable.id, positionTicks: ticks, finished: false)
            return
        }
        guard var current = report else { return }
        current.positionTicks = Self.ticks(engine.clock.currentTime)
        current.isPaused = engine.state == .paused
        report = current
        store.reporter.progress(current, event: event)
    }

    private static func ticks(_ seconds: Double) -> Int64 {
        guard seconds.isFinite, seconds > 0 else { return 0 }
        return Int64(seconds * Double(Ticks.perSecond))
    }
}

private extension [TrackInfo] {
    var embeddedIDs: [Int] { filter { !$0.isExternal }.map(\.id) }
}
