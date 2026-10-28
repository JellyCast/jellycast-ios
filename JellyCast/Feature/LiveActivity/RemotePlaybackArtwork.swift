import UIKit

/// Writes the playing item's image, small, where the widget extension can read it. Without the
/// App Group container (it depends on the signing team) the activity shows the brand mark.
final class RemotePlaybackArtwork {
    private var current: (itemID: String, artworkID: String?)?

    /// The lock screen draws it at most 72 pt wide; three pixels per point.
    private static let pixelWidth = 216
    private static let jpegQuality = 0.8

    func prepare(_ item: RemoteItem, client: JellyfinClient) async -> String? {
        if let current, current.itemID == item.id { return current.artworkID }
        let artworkID = await write(item, client: client)
        current = (item.id, artworkID)
        return artworkID
    }

    func clear() {
        current = nil
        guard let directory = RemotePlaybackArtworkFiles.directory else { return }
        try? FileManager.default.removeItem(at: directory)
    }

    private func write(_ item: RemoteItem, client: JellyfinClient) async -> String? {
        guard let ref = item.image, let directory = RemotePlaybackArtworkFiles.directory else { return nil }
        let url = client.imageURL(ref, type: item.imageType, pixelWidth: Self.pixelWidth)
        guard let image = await ImagePipeline.shared.image(for: url),
              let data = image.jpegData(compressionQuality: Self.jpegQuality)
        else { return nil }
        let artworkID = ref.itemID + "-" + ref.tag
        guard let file = RemotePlaybackArtworkFiles.url(for: artworkID) else { return nil }
        do {
            try? FileManager.default.removeItem(at: directory)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try data.write(to: file, options: .atomic)
            return artworkID
        } catch {
            return nil
        }
    }
}
