import SwiftUI

/// The user's lists to put an item at the bottom of, with a check where it already is.
struct AddToListSheet: View {
    let request: AddToListRequest

    @Environment(ListsStore.self) private var lists
    @Environment(\.dismiss) private var dismiss
    @State private var isNaming = false
    @State private var addingTo: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            SheetTitle(
                title: String(localized: "Add to list"),
                subtitle: String(localized: "\(request.title) goes at the bottom")
            )
            ScrollView {
                VStack(spacing: 10) {
                    rows
                    SheetRow(
                        title: String(localized: "New list…"), systemImage: "plus", isAccented: true
                    ) { isNaming = true } trailing: {}
                }
            }
            .scrollBounceBehavior(.basedOnSize)
        }
        .padding(20)
        .presentationDetents([.medium, .large])
        .presentationBackground(JellyCastColors.surface)
        .listNameAlert("New list", isPresented: $isNaming, confirmTitle: "Create") { name in
            Task {
                if await lists.create(name: name, itemIDs: request.itemIDs) != nil { dismiss() }
            }
        }
        .task { await lists.load() }
    }

    @ViewBuilder
    private var rows: some View {
        if lists.lists.isEmpty, lists.loadState != .loaded {
            ProgressView().frame(maxWidth: .infinity, minHeight: 80)
        }
        ForEach(lists.lists) { list in
            let position = position(in: list)
            CheckedSheetRow(
                title: list.name, detail: detail(list, position: position), isChecked: position != nil
            ) {
                guard position == nil, addingTo == nil else { return }
                addingTo = list.id
                Task {
                    await lists.add(itemIDs: request.itemIDs, to: list.id)
                    dismiss()
                }
            }
            .opacity(addingTo == list.id ? 0.5 : 1)
        }
    }

    /// Where the item is in the list, counted from 1; nil when not everything is in it yet.
    private func position(in list: UserList) -> Int? {
        let itemIDs = Set(list.entries.map(\.itemID))
        guard request.itemIDs.allSatisfy(itemIDs.contains),
              let first = list.entries.firstIndex(where: { $0.itemID == request.itemIDs.first })
        else { return nil }
        return first + 1
    }

    private func detail(_ list: UserList, position: Int?) -> String {
        let count = String(localized: "\(list.entries.count) titles")
        guard let position else { return count }
        return request.itemIDs.count == 1
            ? Format.joined([count, String(localized: "already in it, as \(position)")])
            : Format.joined([count, String(localized: "already in it")])
    }
}

#Preview {
    Color.clear
        .sheet(isPresented: .constant(true)) {
            AddToListSheet(request: AddToListRequest(title: "Interstellar", itemIDs: ["1"]))
        }
        .environment(ListsStore.preview)
        .preferredColorScheme(.dark)
}
