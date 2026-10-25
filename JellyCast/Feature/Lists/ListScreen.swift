import SwiftUI

/// One list in its order: Continue plays from the first item not fully watched and goes on
/// item after item; hold and drag a row to move it, swipe it away to remove it.
struct ListScreen: View {
    let store: LibraryStore
    let listID: String

    @Environment(ListsStore.self) private var lists
    @Environment(AppNavigation.self) private var navigation
    @Environment(\.layout) private var layout
    @State private var isRenaming = false
    @State private var isConfirmingDelete = false

    var body: some View {
        Group {
            if let list = lists.list(id: listID) {
                content(list, progress: ListProgress(list, index: store.index))
            } else if lists.loadState == .loaded {
                Text("This list is gone")
                    .foregroundStyle(JellyCastColors.textMuted)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ProgressView().tint(JellyCastColors.textMuted).frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(JellyCastColors.background)
        .navigationTitle(lists.list(id: listID)?.name ?? "")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) { menu }
        }
        .listNameAlert(
            "Rename list", isPresented: $isRenaming, initialName: lists.list(id: listID)?.name ?? "",
            confirmTitle: "Save"
        ) { name in
            Task { await lists.rename(listID, to: name) }
        }
        .confirmationDialog(
            "Delete this list?", isPresented: $isConfirmingDelete, titleVisibility: .visible
        ) {
            Button("Delete list", role: .destructive) {
                Task { await lists.delete(listID) }
                navigation.goBack()
            }
        } message: {
            Text("The movies and episodes stay in the library.")
        }
        .task { if lists.list(id: listID) == nil { await lists.load() } }
    }

    private func content(_ list: UserList, progress: ListProgress) -> some View {
        List {
            header(progress)
                .listRowInsets(EdgeInsets(top: 4, leading: layout.margin, bottom: 12, trailing: layout.margin))
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
                .moveDisabled(true)
                .deleteDisabled(true)
            ForEach(Array(progress.items.enumerated()), id: \.element.id) { position, item in
                // A button would take the long press that starts moving the row.
                ListItemRow(number: position + 1, playable: item.playable, isNext: item.id == progress.next?.id)
                    .onTapGesture { play(progress, from: position) }
                    .accessibilityAddTraits(.isButton)
                .listRowInsets(EdgeInsets(top: 0, leading: layout.margin, bottom: 0, trailing: layout.margin))
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
            }
            .onMove { source, destination in
                Task { await lists.move(in: listID, from: source, to: destination) }
            }
            .onDelete { offsets in
                let removed = offsets.map { progress.items[$0].entryID }
                Task { for entryID in removed { await lists.remove(entryID: entryID, from: listID) } }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .refreshable { await lists.load() }
    }

    @ViewBuilder
    private func header(_ progress: ListProgress) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(summary(progress))
                .font(.subheadline)
                .foregroundStyle(JellyCastColors.textMuted)
            if !progress.items.isEmpty {
                AccentButton(title: playTitle(progress)) {
                    let start = progress.next.flatMap { next in progress.items.firstIndex { $0.id == next.id } }
                    play(progress, from: start ?? 0, fromStart: start == nil)
                }
            } else {
                Text("Hold a movie, series or episode and choose Add to list…")
                    .font(.subheadline)
                    .foregroundStyle(JellyCastColors.textMuted)
            }
        }
    }

    private var menu: some View {
        Menu {
            if let list = lists.list(id: listID), !list.entries.isEmpty {
                Button("Play from the beginning", systemImage: "arrow.counterclockwise") {
                    play(ListProgress(list, index: store.index), from: 0, fromStart: true)
                }
            }
            Button("Rename", systemImage: "pencil") { isRenaming = true }
            Button("Delete list", systemImage: "trash", role: .destructive) { isConfirmingDelete = true }
        } label: {
            Image(systemName: "ellipsis")
        }
        .accessibilityLabel("More")
    }

    private func summary(_ progress: ListProgress) -> String {
        var parts = [String(localized: "\(progress.items.count) titles")]
        if progress.watchedCount > 0 { parts.append(String(localized: "\(progress.watchedCount) watched")) }
        if progress.next != nil, let left = Format.runtime(progress.remainingTicks) {
            parts.append(String(localized: "\(left) to go"))
        }
        return Format.joined(parts)
    }

    private func playTitle(_ progress: ListProgress) -> String {
        guard let next = progress.next else { return String(localized: "Play from the beginning") }
        guard progress.isStarted else { return String(localized: "Play") }
        return String(localized: "Continue: \(ListPoster.title(of: next.playable))")
    }

    private func play(_ progress: ListProgress, from position: Int, fromStart: Bool = false) {
        guard let list = lists.list(id: listID) else { return }
        var items = progress.items.map(\.playable)
        if fromStart { items[position] = items[position].fromStart }
        navigation.play(PlayQueue(listName: list.name, items: items, startAt: position))
    }
}

private struct ListItemRow: View {
    let number: Int
    let playable: Playable
    let isNext: Bool

    private static let posterSize = CGSize(width: 44, height: 66)
    private static let watchedOpacity = 0.55

    private var isWatched: Bool { playable.watch.played }

    var body: some View {
        HStack(spacing: 12) {
            Text(verbatim: "\(number)")
                .font(.subheadline.weight(isNext ? .bold : .medium))
                .monospacedDigit()
                .foregroundStyle(isNext ? JellyCastColors.accent : JellyCastColors.textMuted)
                .frame(width: 22, alignment: .trailing)
            RemoteImage(ref: ListPoster.of(playable), width: Self.posterSize.width)
                .frame(width: Self.posterSize.width, height: Self.posterSize.height)
                .clipShape(.rect(cornerRadius: 6))
                .opacity(isWatched ? Self.watchedOpacity : 1)
            VStack(alignment: .leading, spacing: 3) {
                Text(ListPoster.title(of: playable))
                    .font(.body.weight(.semibold))
                    .foregroundStyle(isWatched ? JellyCastColors.textMuted : JellyCastColors.text)
                    .lineLimit(1)
                infoLine
                if isNext, let progress = playable.progress {
                    WatchProgressBar(progress: progress, height: 3).padding(.top, 3)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Image(systemName: "line.3.horizontal")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(JellyCastColors.textMuted.opacity(0.7))
                .frame(width: 28)
                .accessibilityHidden(true)
        }
        .padding(.vertical, 7)
        .contentShape(.rect)
    }

    private var infoLine: some View {
        HStack(spacing: 5) {
            if isWatched {
                Image(systemName: "checkmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(JellyCastColors.accent)
            }
            Text(info)
                .font(.subheadline)
                .foregroundStyle(isNext && !isWatched ? JellyCastColors.accent : JellyCastColors.textMuted)
                .lineLimit(1)
        }
    }

    private var info: String {
        let kind: String? = switch playable {
        case .movie(let movie): Format.joined([String(localized: "Movie"), movie.year.map(String.init)])
        case .episode(let episode): episode.name
        }
        let state = isWatched ? String(localized: "watched") : Format.timeLabel(playable)
        return Format.joined([kind, state])
    }
}

#Preview {
    NavigationStack {
        ListScreen(store: LibraryStore(session: .preview, snapshot: .preview), listID: "a")
    }
    .environment(ListsStore.preview)
    .environment(AppNavigation())
    .preferredColorScheme(.dark)
}
