import Foundation

/// Something playing on another device under the same account, as the server last heard it.
nonisolated struct RemoteSession: Sendable, Identifiable, Equatable {
    enum PlayMethod: String, Sendable {
        case directPlay = "DirectPlay"
        case directStream = "DirectStream"
        case transcode = "Transcode"
    }

    let id: String
    let deviceID: String
    var deviceName: String
    let item: RemoteItem
    var positionTicks: Int64
    var isPaused: Bool
    let playMethod: PlayMethod?
    var checkedInAt: Date?
    /// The TV app listens for commands; without it the session can only be watched.
    let canControl: Bool
    var audioStreamIndex: Int?
    var subtitleStreamIndex: Int?

    private static let maxExtrapolationSeconds = 30.0
    /// Our TV apps report every 10 s, paused or not; three missed reports mean the app is gone
    /// (closed, crashed, TV off) without the stop report that would clear it on the server.
    private static let silenceBeforeStoppedSeconds = 30.0

    func isSilent(at date: Date) -> Bool {
        guard let checkedInAt else { return false }
        return date.timeIntervalSince(checkedInAt) > Self.silenceBeforeStoppedSeconds
    }

    /// The position now: the reported one, run on since the report while playing.
    func position(at date: Date) -> Int64 {
        guard !isPaused, let checkedInAt else { return positionTicks }
        let elapsed = min(max(date.timeIntervalSince(checkedInAt), 0), Self.maxExtrapolationSeconds)
        let position = positionTicks + Int64(elapsed * Double(Ticks.perSecond))
        guard let runtime = item.runtimeTicks else { return position }
        return min(position, runtime)
    }
}

/// A TV app that takes commands right now, playing or not.
nonisolated struct RemoteDevice: Sendable, Identifiable, Equatable {
    /// The session id: commands go to the session.
    let id: String
    let deviceID: String
    var name: String
    let isPlaying: Bool
    let lastActivity: Date?
    /// Its address on the home network, as the server saw it.
    let address: String?
    /// Only an Android TV can be woken from the iPhone.
    let isAndroidTV: Bool
}

nonisolated struct RemoteSnapshot: Sendable {
    let playing: [RemoteSession]
    let devices: [RemoteDevice]
}

nonisolated struct RemoteItem: Sendable, Equatable {
    let id: String
    let name: String
    let seriesName: String?
    let seasonNumber: Int?
    let episodeNumber: Int?
    let runtimeTicks: Int64?
    let image: ImageRef?
    let imageType: JellyfinClient.ImageType
}

private nonisolated struct SessionDTO: Decodable {
    struct Playback: Decodable {
        let PositionTicks: Int64?
        let IsPaused: Bool?
        let PlayMethod: String?
        let AudioStreamIndex: Int?
        let SubtitleStreamIndex: Int?
    }

    struct NowPlaying: Decodable {
        let Id: String
        let Name: String
        let `Type`: String?
        let SeriesName: String?
        let ParentIndexNumber: Int?
        let IndexNumber: Int?
        let RunTimeTicks: Int64?
        let ImageTags: [String: String]?
        let BackdropImageTags: [String]?
    }

    let Id: String
    let UserId: String?
    let DeviceId: String?
    let DeviceName: String?
    let LastPlaybackCheckIn: Date?
    let LastActivityDate: Date?
    let RemoteEndPoint: String?
    let SupportsRemoteControl: Bool?
    let PlayState: Playback?
    let NowPlayingItem: NowPlaying?

    func remoteSession() -> RemoteSession? {
        guard let item = NowPlayingItem else { return nil }
        return RemoteSession(
            id: Id,
            deviceID: DeviceId ?? Id,
            deviceName: DeviceName ?? "",
            item: Self.remoteItem(item),
            positionTicks: PlayState?.PositionTicks ?? 0,
            isPaused: PlayState?.IsPaused ?? false,
            playMethod: PlayState?.PlayMethod.flatMap(RemoteSession.PlayMethod.init(rawValue:)),
            checkedInAt: LastPlaybackCheckIn,
            canControl: SupportsRemoteControl ?? false,
            audioStreamIndex: PlayState?.AudioStreamIndex,
            subtitleStreamIndex: PlayState?.SubtitleStreamIndex
        )
    }

    func remoteDevice() -> RemoteDevice? {
        guard SupportsRemoteControl == true else { return nil }
        let deviceID = DeviceId ?? Id
        return RemoteDevice(
            id: Id, deviceID: deviceID, name: DeviceName ?? "",
            isPlaying: NowPlayingItem != nil, lastActivity: LastActivityDate,
            address: RemoteEndPoint, isAndroidTV: !deviceID.hasPrefix(Self.webOSDevicePrefix)
        )
    }

    /// The webOS app makes its device ids like this; the Android TV app uses the SDK's.
    private static let webOSDevicePrefix = "webos-"

    /// An episode shows its own still; a movie its backdrop, or its poster without one.
    private static func remoteItem(_ item: NowPlaying) -> RemoteItem {
        let isEpisode = item.Type == "Episode"
        let backdrop = item.BackdropImageTags?.first
        let image: ImageRef?
        let imageType: JellyfinClient.ImageType
        if !isEpisode, let backdrop {
            image = ImageRef(itemID: item.Id, tag: backdrop)
            imageType = .backdrop
        } else {
            image = item.ImageTags?["Primary"].map { ImageRef(itemID: item.Id, tag: $0) }
            imageType = .primary
        }
        return RemoteItem(
            id: item.Id,
            name: item.Name,
            seriesName: isEpisode ? item.SeriesName : nil,
            seasonNumber: isEpisode ? item.ParentIndexNumber : nil,
            episodeNumber: isEpisode ? item.IndexNumber : nil,
            runtimeTicks: item.RunTimeTicks,
            image: image,
            imageType: imageType
        )
    }
}

extension JellyfinClient {
    private static let sessionActivityWindowSeconds = 300

    /// The user's other devices: what they play, most recently reported first, and which take
    /// commands. `controllableByUserId` would drop sessions that can't be controlled, so the
    /// filtering on user and device happens here.
    func userSessions(userID: String) async throws -> RemoteSnapshot {
        let sessions: [SessionDTO] = try await send(
            "Sessions",
            query: [URLQueryItem(name: "activeWithinSeconds", value: String(Self.sessionActivityWindowSeconds))]
        )
        let own = sessions.filter { $0.UserId == userID && $0.DeviceId != deviceID }
        return RemoteSnapshot(
            playing: own.compactMap { $0.remoteSession() }
                .sorted { ($0.checkedInAt ?? .distantPast) > ($1.checkedInAt ?? .distantPast) },
            devices: own.compactMap { $0.remoteDevice() }
        )
    }
}

/// What the now playing screen can ask a TV app to do.
nonisolated enum RemoteCommand: Sendable, Equatable {
    case pause, unpause, stop, nextEpisode
    /// Replaces what plays on the TV.
    case play(itemID: String, startTicks: Int64, streams: StreamSelection? = nil)
    case seek(positionTicks: Int64)
    case audioStream(index: Int)
    /// `-1` turns subtitles off.
    case subtitleStream(index: Int)

    static let subtitlesOff = -1

    var changesItem: Bool {
        switch self {
        case .nextEpisode, .play: true
        default: false
        }
    }
}

extension JellyfinClient {
    func send(_ command: RemoteCommand, toSession sessionID: String) async throws {
        let path = "Sessions/\(sessionID)"
        switch command {
        case .pause: _ = try await data(path + "/Playing/Pause", method: "POST")
        case .unpause: _ = try await data(path + "/Playing/Unpause", method: "POST")
        case .stop: _ = try await data(path + "/Playing/Stop", method: "POST")
        case .nextEpisode: _ = try await data(path + "/Playing/NextTrack", method: "POST")
        case .play(let itemID, let startTicks, let streams):
            var query = [
                URLQueryItem(name: "playCommand", value: "PlayNow"),
                URLQueryItem(name: "itemIds", value: itemID),
                URLQueryItem(name: "startPositionTicks", value: String(startTicks)),
            ]
            if let audio = streams?.audio { query.append(URLQueryItem(name: "audioStreamIndex", value: String(audio))) }
            if let subtitle = streams?.subtitle {
                query.append(URLQueryItem(name: "subtitleStreamIndex", value: String(subtitle)))
            }
            _ = try await data(path + "/Playing", method: "POST", query: query)
        case .seek(let ticks):
            _ = try await data(
                path + "/Playing/Seek", method: "POST",
                query: [URLQueryItem(name: "seekPositionTicks", value: String(ticks))]
            )
        case .audioStream(let index):
            try await sendGeneralCommand("SetAudioStreamIndex", index: index, path: path)
        case .subtitleStream(let index):
            try await sendGeneralCommand("SetSubtitleStreamIndex", index: index, path: path)
        }
    }

    private func sendGeneralCommand(_ name: String, index: Int, path: String) async throws {
        struct Body: Encodable {
            let Name: String
            let Arguments: [String: String]
        }
        let body = try JSONEncoder().encode(Body(Name: name, Arguments: ["Index": String(index)]))
        _ = try await data(path + "/Command", method: "POST", body: body)
    }
}
