import Foundation
import OSLog
import SwiftUI

/// The user's lists, loaded when they are first opened. Changes show at once and go to the
/// server after; when the server refuses one, the lists are loaded again.
@Observable
final class ListsStore {
    enum LoadState: Equatable {
        case idle, loading, loaded
        case failed(String)
    }

    private(set) var lists: [UserList] = []
    private(set) var loadState = LoadState.idle
    /// Shown once when a change could not be saved.
    var changeError: String?

    private let session: Session
    private static let logger = Logger(subsystem: "nl.jellycast.ios", category: "lists")

    init(session: Session, lists: [UserList] = []) {
        self.session = session
        self.lists = lists
        if !lists.isEmpty { loadState = .loaded }
    }

    static var preview: ListsStore {
        ListsStore(session: .preview, lists: [
            UserList(id: "a", name: "Nolan", entries: [
                .init(id: "e1", itemID: "1"), .init(id: "e2", itemID: "2"),
            ]),
            UserList(id: "b", name: "Christmas", entries: []),
        ])
    }

    private var client: JellyfinClient { session.client }

    func list(id: String) -> UserList? {
        lists.first { $0.id == id }
    }

    /// Shows what was loaded before right away; another device may have changed the lists since.
    func load() async {
        if lists.isEmpty { loadState = .loading }
        do {
            lists = try await client.lists(userID: session.userID)
            loadState = .loaded
        } catch is CancellationError {
            if loadState == .loading { loadState = .idle }
        } catch {
            Self.logger.error("Loading lists failed: \(error.localizedDescription, privacy: .public)")
            if lists.isEmpty { loadState = .failed(error.localizedDescription) }
        }
    }

    /// Returns the new list's id.
    @discardableResult
    func create(name: String, itemIDs: [String]) async -> String? {
        do {
            let id = try await client.createList(name: name, itemIDs: itemIDs, userID: session.userID)
            let entries = try await client.listEntries(listID: id, userID: session.userID)
            lists.append(UserList(id: id, name: name, entries: entries))
            lists.sort { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
            return id
        } catch {
            fail(error)
            return nil
        }
    }

    func add(itemIDs: [String], to listID: String) async {
        do {
            try await client.addToList(listID: listID, itemIDs: itemIDs, userID: session.userID)
            let entries = try await client.listEntries(listID: listID, userID: session.userID)
            update(listID) { $0.entries = entries }
        } catch {
            fail(error)
        }
    }

    func remove(entryID: String, from listID: String) async {
        update(listID) { $0.entries.removeAll { $0.id == entryID } }
        await save { try await $0.removeFromList(listID: listID, entryIDs: [entryID]) }
    }

    func move(in listID: String, from source: IndexSet, to destination: Int) async {
        guard let list = list(id: listID), let from = source.first else { return }
        var entries = list.entries
        entries.move(fromOffsets: source, toOffset: destination)
        guard entries != list.entries,
              let newIndex = entries.firstIndex(where: { $0.id == list.entries[from].id })
        else { return }
        update(listID) { $0.entries = entries }
        await save { try await $0.moveInList(listID: listID, entryID: list.entries[from].id, to: newIndex) }
    }

    func rename(_ listID: String, to name: String) async {
        update(listID) { $0.name = name }
        await save { try await $0.renameList(listID: listID, name: name) }
    }

    func delete(_ listID: String) async {
        lists.removeAll { $0.id == listID }
        await save { try await $0.deleteList(listID: listID) }
    }

    private func update(_ listID: String, _ change: (inout UserList) -> Void) {
        guard let position = lists.firstIndex(where: { $0.id == listID }) else { return }
        change(&lists[position])
    }

    private func save(_ change: (JellyfinClient) async throws -> Void) async {
        do {
            try await change(client)
        } catch {
            fail(error)
            await load()
        }
    }

    private func fail(_ error: Error) {
        guard !(error is CancellationError) else { return }
        Self.logger.error("Changing a list failed: \(error.localizedDescription, privacy: .public)")
        changeError = error.localizedDescription
    }
}

/// A list read against the library: what it holds that this app can play, and how far along it is.
nonisolated struct ListProgress: Sendable {
    struct Item: Sendable, Hashable, Identifiable {
        let entryID: String
        let playable: Playable

        var id: String { entryID }
    }

    let items: [Item]

    init(_ list: UserList, index: LibraryIndex?) {
        items = list.entries.compactMap { entry in
            index?.playable(id: entry.itemID).map { Item(entryID: entry.id, playable: $0) }
        }
    }

    var watchedCount: Int { items.count { $0.playable.watch.played } }

    /// The first item not fully watched: where Continue picks up.
    var next: Item? { items.first { !$0.playable.watch.played } }

    var isStarted: Bool { items.contains { $0.playable.watch.played || $0.playable.watch.isInProgress } }

    var remainingTicks: Int64 {
        items.filter { !$0.playable.watch.played }.reduce(0) { $0 + ($1.playable.remainingTicks ?? 0) }
    }
}
