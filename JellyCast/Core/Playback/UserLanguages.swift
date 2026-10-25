import Foundation
import OSLog

/// The user's languages from the server, loaded once per launch so the track sheet can sort by
/// them without waiting.
@Observable
final class UserLanguages {
    static let shared = UserLanguages()

    private(set) var codes: [String] = []

    private static let logger = Logger(subsystem: "nl.jellycast.ios", category: "player")

    func load(client: JellyfinClient) async {
        do {
            codes = try await client.preferredLanguages()
        } catch is CancellationError {
            return
        } catch {
            Self.logger.debug("No preferred languages: \(error, privacy: .public)")
        }
    }
}
