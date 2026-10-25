import Foundation

/// The last synced library on disk, so the app can show it before the server answers, or offline.
nonisolated enum LibraryCache {
    private static var fileURL: URL {
        URL.applicationSupportDirectory.appending(path: "library.json")
    }

    @concurrent
    static func load(serverID: String, userID: String) async -> LibrarySnapshot? {
        guard let data = try? Data(contentsOf: fileURL),
              let snapshot = try? decoder.decode(LibrarySnapshot.self, from: data),
              snapshot.formatVersion == LibrarySnapshot.formatVersion,
              snapshot.serverID == serverID, snapshot.userID == userID
        else { return nil }
        return snapshot
    }

    @concurrent
    static func save(_ snapshot: LibrarySnapshot) async throws {
        let data = try encoder.encode(snapshot)
        try FileManager.default.createDirectory(
            at: URL.applicationSupportDirectory, withIntermediateDirectories: true
        )
        try data.write(to: fileURL, options: .atomic)
        var url = fileURL
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try url.setResourceValues(values)
    }

    static func delete() {
        try? FileManager.default.removeItem(at: fileURL)
    }

    private static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        return encoder
    }

    private static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        return decoder
    }
}
