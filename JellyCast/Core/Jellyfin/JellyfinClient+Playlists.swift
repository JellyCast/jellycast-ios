import Foundation

/// A playlist as the server keeps it: its name and its entries in order.
nonisolated struct UserList: Sendable, Hashable, Identifiable {
    /// One place in a list; the same item can be in a list twice, each with its own entry id.
    struct Entry: Sendable, Hashable, Identifiable {
        let id: String
        let itemID: String
    }

    let id: String
    var name: String
    var entries: [Entry]
}

extension JellyfinClient {
    /// The user's video playlists with their entries, sorted by name.
    func lists(userID: String) async throws -> [UserList] {
        struct Item: Decodable { let Id: String; let Name: String; let MediaType: String? }
        struct Response: Decodable { let Items: [Item] }
        let response: Response = try await send(
            "Items",
            query: [
                URLQueryItem(name: "userId", value: userID),
                URLQueryItem(name: "recursive", value: "true"),
                URLQueryItem(name: "includeItemTypes", value: "Playlist"),
                URLQueryItem(name: "sortBy", value: "SortName"),
            ]
        )
        let playlists = response.Items.filter { $0.MediaType != "Audio" }
        return try await withThrowingTaskGroup(of: (Int, UserList).self) { group in
            for (position, playlist) in playlists.enumerated() {
                group.addTask {
                    let entries = try await listEntries(listID: playlist.Id, userID: userID)
                    return (position, UserList(id: playlist.Id, name: playlist.Name, entries: entries))
                }
            }
            var lists: [(Int, UserList)] = []
            for try await list in group { lists.append(list) }
            return lists.sorted { $0.0 < $1.0 }.map(\.1)
        }
    }

    func listEntries(listID: String, userID: String) async throws -> [UserList.Entry] {
        struct Item: Decodable { let Id: String; let PlaylistItemId: String? }
        struct Response: Decodable { let Items: [Item] }
        let response: Response = try await send(
            "Playlists/\(listID)/Items",
            query: [
                URLQueryItem(name: "userId", value: userID),
                URLQueryItem(name: "enableImages", value: "false"),
                URLQueryItem(name: "enableUserData", value: "false"),
            ]
        )
        return response.Items.compactMap { item in
            item.PlaylistItemId.map { UserList.Entry(id: $0, itemID: item.Id) }
        }
    }

    /// A season or series in `itemIDs` is added by the server as its episodes.
    func createList(name: String, itemIDs: [String], userID: String) async throws -> String {
        struct Response: Decodable { let Id: String }
        let body: [String: JSONValue] = [
            "Name": .string(name),
            "UserId": .string(userID),
            "MediaType": .string("Video"),
            "Ids": .array(itemIDs.map(JSONValue.string)),
        ]
        let response: Response = try await send(
            "Playlists", method: "POST", body: try JSONEncoder().encode(body)
        )
        return response.Id
    }

    func addToList(listID: String, itemIDs: [String], userID: String) async throws {
        _ = try await data(
            "Playlists/\(listID)/Items", method: "POST",
            query: [
                URLQueryItem(name: "ids", value: itemIDs.joined(separator: ",")),
                URLQueryItem(name: "userId", value: userID),
            ]
        )
    }

    func removeFromList(listID: String, entryIDs: [String]) async throws {
        _ = try await data(
            "Playlists/\(listID)/Items", method: "DELETE",
            query: [URLQueryItem(name: "entryIds", value: entryIDs.joined(separator: ","))]
        )
    }

    func moveInList(listID: String, entryID: String, to newIndex: Int) async throws {
        _ = try await data("Playlists/\(listID)/Items/\(entryID)/Move/\(newIndex)", method: "POST")
    }

    func renameList(listID: String, name: String) async throws {
        let body: [String: JSONValue] = ["Name": .string(name)]
        _ = try await data("Playlists/\(listID)", method: "POST", body: try JSONEncoder().encode(body))
    }

    func deleteList(listID: String) async throws {
        _ = try await data("Items/\(listID)", method: "DELETE")
    }
}
