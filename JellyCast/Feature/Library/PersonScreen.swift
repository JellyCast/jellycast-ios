import SwiftUI

/// The movies and series in the library that one person appears in.
struct PersonScreen: View {
    let store: LibraryStore
    let person: PersonResult

    @State private var itemIDs: [String]?
    @State private var error: String?

    var body: some View {
        Group {
            if let itemIDs, let index = store.index {
                let entries = LibraryListing.entries(index, kind: .all).filter { itemIDs.contains($0.id) }
                EntryList(entries: entries, index: index)
            } else if let error {
                ContentErrorView(message: error) { Task { await load() } }
            } else {
                ProgressView().tint(JellyCastColors.textMuted).frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(JellyCastColors.background)
        .navigationTitle(person.name)
        .task { await load() }
    }

    private func load() async {
        error = nil
        do {
            itemIDs = try await store.session.client.itemIDs(withPerson: person.id, userID: store.session.userID)
        } catch is CancellationError {
        } catch {
            self.error = error.localizedDescription
        }
    }
}

private struct EntryList: View {
    let entries: [LibraryEntry]
    let index: LibraryIndex

    @Environment(\.layout) private var layout

    var body: some View {
        ScrollView {
            if entries.isEmpty {
                Text("Nothing here")
                    .foregroundStyle(JellyCastColors.textMuted)
                    .padding(.top, 48)
            }
            LibraryTileGrid(entries: entries, index: index)
                .padding(.top, 12)
                .padding(.horizontal, layout.margin)
            .padding(.bottom, 24)
        }
    }
}
