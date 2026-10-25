import Foundation

/// A server transcode to HLS: the playlist to play and the play session id the reports must carry,
/// so the server stops the transcode when playback stops.
nonisolated struct TranscodeStream: Sendable {
    let url: URL
    let playSessionID: String
}

extension JellyfinClient {
    /// Asks the server for an HEVC + stereo AAC transcode capped at a width and bitrate.
    /// Jellyfin 10.11 encodes HEVC in 8 bit only, so HDR sources come out tone-mapped to SDR.
    /// A text subtitle comes along as a WebVTT rendition; an image subtitle is burned in.
    func transcodeStream(
        itemID: String, mediaSourceID: String, userID: String, maxWidth: Int, maxBitsPerSecond: Int,
        audioStreamIndex: Int?, subtitleStreamIndex: Int?
    ) async throws -> TranscodeStream {
        let request = PlaybackInfoRequest(
            UserId: userID, MediaSourceId: mediaSourceID, MaxStreamingBitrate: maxBitsPerSecond,
            AudioStreamIndex: audioStreamIndex, SubtitleStreamIndex: subtitleStreamIndex ?? Self.noSubtitle,
            DeviceProfile: .hevcTranscode(maxBitsPerSecond: maxBitsPerSecond)
        )
        let response: PlaybackInfoResponse = try await send(
            "Items/\(itemID)/PlaybackInfo", method: "POST", body: try JSONEncoder().encode(request)
        )
        guard let source = response.MediaSources.first(where: { $0.Id == mediaSourceID }),
              let path = source.TranscodingUrl,
              let url = URL(string: path + "&MaxWidth=\(maxWidth)", relativeTo: serverURL)?.absoluteURL
        else { throw JellyfinError.badStatus(0) }
        return TranscodeStream(url: url, playSessionID: response.PlaySessionId)
    }

    /// Without it the server picks a default subtitle track itself.
    private static let noSubtitle = -1
}

private nonisolated struct PlaybackInfoRequest: Encodable {
    let UserId: String
    let MediaSourceId: String
    let MaxStreamingBitrate: Int
    let AudioStreamIndex: Int?
    let SubtitleStreamIndex: Int
    let DeviceProfile: TranscodeDeviceProfile
    let EnableDirectPlay = false
    let EnableDirectStream = false
    let EnableTranscoding = true
    let AllowVideoStreamCopy = false
}

private nonisolated struct PlaybackInfoResponse: Decodable {
    struct Source: Decodable {
        let Id: String
        let TranscodingUrl: String?
    }

    let MediaSources: [Source]
    let PlaySessionId: String
}

private nonisolated struct TranscodeDeviceProfile: Encodable {
    struct TranscodingProfile: Encodable {
        let `Type` = "Video"
        let Container = "mp4"
        let `Protocol` = "hls"
        let VideoCodec = "hevc"
        let AudioCodec = "aac"
        let Context = "Streaming"
        let MaxAudioChannels = "2"
        let MinSegments = 1
        let BreakOnNonKeyFrames = true
    }

    struct SubtitleProfile: Encodable {
        let Format = "vtt"
        let Method = "Hls"
    }

    let MaxStreamingBitrate: Int
    let DirectPlayProfiles: [String] = []
    let TranscodingProfiles = [TranscodingProfile()]
    let SubtitleProfiles = [SubtitleProfile()]

    static func hevcTranscode(maxBitsPerSecond: Int) -> TranscodeDeviceProfile {
        TranscodeDeviceProfile(MaxStreamingBitrate: maxBitsPerSecond)
    }
}
