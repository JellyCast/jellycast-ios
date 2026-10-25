import Foundation

/// A list playing item after item, in place of the next episode.
nonisolated struct PlayQueue: Sendable, Hashable {
    let listName: String
    let items: [Playable]
    private(set) var position: Int

    init(listName: String, items: [Playable], startAt position: Int) {
        self.listName = listName
        self.items = items
        self.position = position
    }

    var current: Playable? { items.indices.contains(position) ? items[position] : nil }

    var next: Playable? {
        let after = position + 1
        return items.indices.contains(after) ? items[after] : nil
    }

    mutating func advance() {
        position += 1
    }

    /// Jumps to the item when it is in the list; false when it is not.
    mutating func moveTo(_ playable: Playable) -> Bool {
        guard let found = items.firstIndex(where: { $0.id == playable.id }) else { return false }
        position = found
        return true
    }
}
