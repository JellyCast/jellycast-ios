import Foundation

/// The audio and subtitle track as the server's stream indexes, handed over between the iPhone and
/// a TV. `nil` leaves the choice to the player; a subtitle of `RemoteCommand.subtitlesOff` is off.
nonisolated struct StreamSelection: Hashable, Sendable {
    var audio: Int?
    var subtitle: Int?

    /// The player numbers the file's own tracks; the server also lists external subtitle files.
    /// Both keep the file's order, so the n-th embedded track is the same track on either side.
    static func playerTrack(forServer index: Int, server: [Int], player: [Int]) -> Int? {
        server.firstIndex(of: index).flatMap { player.indices.contains($0) ? player[$0] : nil }
    }

    static func serverIndex(forPlayer track: Int, server: [Int], player: [Int]) -> Int? {
        player.firstIndex(of: track).flatMap { server.indices.contains($0) ? server[$0] : nil }
    }
}
