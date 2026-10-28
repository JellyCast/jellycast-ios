import SwiftUI

/// Library: everything as a grid of posters, filtered by type, genre and watch status, sorted,
/// and searchable by title, person and episode from the bar above the tab bar.
struct LibraryScreen: View {
    let store: LibraryStore
    let search: SearchModel

    @State private var filters = LibraryFilters()
    @FocusState private var isSearchFocused: Bool

    var body: some View {
        @Bindable var search = search
        Group {
            if let index = store.index {
                LibraryGrid(index: index, search: search, filters: $filters, isSearching: $isSearchFocused)
            } else if case .failed(let message) = store.syncState {
                ContentErrorView(message: message) { Task { await store.refresh() } }
            } else {
                LibrarySkeleton()
            }
        }
        .background(JellyCastColors.background)
        .safeAreaInset(edge: .top) { SyncProblemOverlay(store: store) }
        .safeAreaInset(edge: .bottom) {
            LibrarySearchBar(query: $search.query, isFocused: $isSearchFocused) {
                search.remember()
            } filter: {
                LibraryFilterMenu(filters: $filters, genres: genreCounts)
            }
        }
        .animation(.easeOut(duration: 0.2), value: store.syncFailure)
        .toolbar(.hidden, for: .navigationBar)
        .onChange(of: search.query, initial: true) { search.updateEpisodes(index: store.index) }
        .onChange(of: store.snapshot?.syncedAt) { search.updateEpisodes(index: store.index) }
        // A search looks in everything; the status filter would hide what was already watched.
        .onChange(of: search.trimmedQuery.isEmpty) { _, isEmpty in
            if !isEmpty { filters.status = nil }
        }
        .task(id: search.trimmedQuery) { await search.searchPeople(session: store.session) }
        .refreshable { await store.refresh() }
    }

    private var genreCounts: [(genre: String, count: Int)] {
        guard let index = store.index else { return [] }
        return LibraryListing.genreCounts(LibraryListing.entries(index, kind: filters.kind))
    }
}

struct LibraryFilters: Equatable {
    var kind = LibraryKind.all
    var genre: String?
    var status: WatchStatus? = .notStarted
    var sort = LibrarySort.newest

    var isNarrowed: Bool { kind != .all || genre != nil || status != nil }
}

private struct LibraryGrid: View {
    let index: LibraryIndex
    let search: SearchModel
    @Binding var filters: LibraryFilters
    var isSearching: FocusState<Bool>.Binding

    @Environment(AppNavigation.self) private var navigation
    @Environment(\.layout) private var layout

    var body: some View {
        let term = search.trimmedQuery
        let entries = LibraryListing.entries(index, kind: filters.kind)
        let matching = LibraryListing.filtered(entries, genre: filters.genre, query: term)
        let sections = LibraryListing.sections(matching, status: filters.status, sort: filters.sort)
        let episodes = filters.kind == .movies || filters.genre != nil ? [] : search.episodes
        let people = term.isEmpty ? [] : search.people
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                ActiveFilterChips(filters: $filters, entries: matching)
                if isSearching.wrappedValue, term.isEmpty, !search.recentSearches.isEmpty {
                    recentSearches
                }
                if sections.isEmpty, people.isEmpty, episodes.isEmpty {
                    Group {
                        if term.isEmpty { Text("Nothing here") } else { Text("No results for “\(term)”") }
                    }
                    .foregroundStyle(JellyCastColors.textMuted)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 48)
                }
                ForEach(sections) { section in
                    ListSectionLabel(text: section.title)
                        .padding(.top, 18)
                        .padding(.bottom, 10)
                    LibraryTileGrid(entries: section.entries, index: index) { search.remember() }
                }
                if !people.isEmpty {
                    ListSectionLabel(text: String(localized: "People")).padding(.top, 18).padding(.bottom, 8)
                    ForEach(people) { person in
                        PersonRow(person: person) {
                            search.remember()
                            navigation.open(.person(person))
                        }
                    }
                }
                if !episodes.isEmpty {
                    ListSectionLabel(text: String(localized: "Episodes")).padding(.top, 18).padding(.bottom, 8)
                    ForEach(episodes) { episode in
                        EpisodeResultRow(episode: episode) {
                            search.remember()
                            navigation.open(.series(id: episode.seriesID))
                        }
                        .mediaContextMenu(.episode(episode), index: index)
                        .availableOffline(episode.seriesID)
                    }
                }
            }
            .padding(.horizontal, layout.margin)
            .padding(.bottom, 24)
        }
        .dismissesKeyboard(isSearching)
    }

    @ViewBuilder
    private var recentSearches: some View {
        ListSectionLabel(text: String(localized: "Recent searches")).padding(.top, 10).padding(.bottom, 4)
        ForEach(search.recentSearches, id: \.self) { term in
            RecentSearchRow(term: term) { search.query = term } onForget: { search.forget(term) }
        }
    }
}

/// Posters in rows as wide as the screen allows: three on the iPhone, more on the iPad.
struct LibraryTileGrid: View {
    let entries: [LibraryEntry]
    let index: LibraryIndex
    var onOpen: () -> Void = {}

    @Environment(\.layout) private var layout
    @State private var width: CGFloat = 0

    var body: some View {
        let metrics = TileMetrics(isRegular: layout.isRegular)
        LazyVStack(alignment: .leading, spacing: metrics.rowSpacing) {
            ForEach(rows(metrics)) { row in
                HStack(alignment: .top, spacing: metrics.spacing) {
                    ForEach(row.entries) { entry in
                        LibraryTile(entry: entry, index: index)
                            .simultaneousGesture(TapGesture().onEnded(onOpen))
                    }
                    ForEach(row.entries.count..<row.columns, id: \.self) { _ in
                        Color.clear.frame(maxWidth: .infinity)
                    }
                }
            }
        }
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
    }

    /// Rows of their own: a `LazyVGrid` inside the outer `LazyVStack` stayed empty after the
    /// kind changed.
    private func rows(_ metrics: TileMetrics) -> [TileRow] {
        let columns = max(metrics.minColumns, Int((width + metrics.spacing) / (metrics.minWidth + metrics.spacing)))
        return stride(from: 0, to: entries.count, by: columns).map { start in
            TileRow(entries: Array(entries[start..<min(start + columns, entries.count)]), columns: columns)
        }
    }
}

private struct TileMetrics {
    let minWidth: CGFloat
    let spacing: CGFloat
    let rowSpacing: CGFloat
    let minColumns: Int

    init(isRegular: Bool) {
        minWidth = isRegular ? 150 : 100
        spacing = isRegular ? 20 : 12
        rowSpacing = isRegular ? 24 : 18
        minColumns = 3
    }
}

private struct TileRow: Identifiable {
    let entries: [LibraryEntry]
    let columns: Int

    var id: String { entries.map(\.id).joined(separator: "|") }
}

/// The search field and the filter button, floating above the tab bar within thumb reach.
private struct LibrarySearchBar<Filter: View>: View {
    @Binding var query: String
    var isFocused: FocusState<Bool>.Binding
    let onSubmit: () -> Void
    @ViewBuilder var filter: Filter

    @Environment(\.layout) private var layout

    private static var height: CGFloat { 48 }

    var body: some View {
        GlassEffectContainer(spacing: 10) {
            HStack(spacing: 10) {
                field
                filter
                    .frame(width: Self.height, height: Self.height)
                    .glassEffect(.regular.interactive(), in: .circle)
            }
        }
        .padding(.horizontal, layout.margin)
        .padding(.bottom, 8)
    }

    private var field: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").foregroundStyle(JellyCastColors.textMuted)
            TextField("Movies, series, people", text: $query)
                .focused(isFocused)
                .submitLabel(.search)
                .onSubmit(onSubmit)
                .autocorrectionDisabled()
                .foregroundStyle(JellyCastColors.text)
            if !query.isEmpty {
                Button {
                    query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(JellyCastColors.textMuted)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear")
            }
        }
        .padding(.horizontal, 16)
        .frame(height: Self.height)
        .glassEffect(.regular.interactive(), in: .capsule)
    }
}

/// Kind, watch status, genre and order in one menu behind the button next to search.
private struct LibraryFilterMenu: View {
    @Binding var filters: LibraryFilters
    let genres: [(genre: String, count: Int)]

    @Environment(AppNavigation.self) private var navigation

    var body: some View {
        Menu {
            Picker("Kind", selection: $filters.kind) {
                Text("All").tag(LibraryKind.all)
                Text("Series").tag(LibraryKind.series)
                Text("Movies").tag(LibraryKind.movies)
            }
            .pickerStyle(.inline)
            Picker("Status", selection: $filters.status) {
                Text("Everything").tag(WatchStatus?.none)
                Text("Not watched").tag(WatchStatus?.some(.notStarted))
                Text("In progress").tag(WatchStatus?.some(.inProgress))
                Text("Watched").tag(WatchStatus?.some(.watched))
            }
            .pickerStyle(.inline)
            Picker("Genre", selection: $filters.genre) {
                Text("All genres").tag(String?.none)
                ForEach(genres, id: \.genre) { item in
                    Text(verbatim: Format.joined([Genres.displayName(item.genre), String(item.count)]))
                        .tag(Optional(item.genre))
                }
            }
            .pickerStyle(.menu)
            Picker("Sort", selection: $filters.sort) {
                Text("Newest").tag(LibrarySort.newest)
                Text("A–Z").tag(LibrarySort.title)
                Text("Year").tag(LibrarySort.year)
                Text("Length").tag(LibrarySort.length)
            }
            .pickerStyle(.menu)
            Section {
                Button("Lists", systemImage: "list.number") { navigation.open(.lists) }
            }
        } label: {
            Image(systemName: "line.3.horizontal.decrease")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(filters.isNarrowed ? JellyCastColors.accent : JellyCastColors.text)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(.circle)
        }
        .accessibilityLabel("Filter and sort")
    }
}

/// What narrows the grid now, each with a cross to drop it; nothing when everything shows.
private struct ActiveFilterChips: View {
    @Binding var filters: LibraryFilters
    let entries: [LibraryEntry]

    var body: some View {
        if filters.isNarrowed {
            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    if filters.kind != .all {
                        chip(filters.kind == .series ? "Series" : "Movies") { filters.kind = .all }
                    }
                    if let status = filters.status {
                        chip(statusTitle(status), count: entries.count { $0.status == status }) {
                            filters.status = nil
                        }
                    }
                    if let genre = filters.genre {
                        chip(LocalizedStringKey(Genres.displayName(genre))) { filters.genre = nil }
                    }
                }
            }
            .scrollIndicators(.hidden)
            .padding(.top, 8)
        }
    }

    private func statusTitle(_ status: WatchStatus) -> LocalizedStringKey {
        switch status {
        case .notStarted: "Not watched"
        case .inProgress: "In progress"
        case .watched: "Watched"
        }
    }

    private func chip(_ title: LocalizedStringKey, count: Int? = nil, onClear: @escaping () -> Void) -> some View {
        Button(action: onClear) {
            HStack(spacing: 6) {
                Text(title)
                if let count { Text(count, format: .number).opacity(0.7) }
                Image(systemName: "xmark").font(.caption2.weight(.bold))
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(JellyCastColors.text)
            .padding(.horizontal, 12)
            .frame(height: 32)
            .background(JellyCastColors.rail, in: .capsule)
        }
        .buttonStyle(PressedOpacityButtonStyle())
    }
}

private struct LibrarySkeleton: View {
    private static let columns = 3
    private static let rows = 4

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            RoundedRectangle(cornerRadius: 4).fill(JellyCastColors.surface).frame(width: 120, height: 14)
            ForEach(0..<Self.rows, id: \.self) { _ in
                HStack(spacing: 12) {
                    ForEach(0..<Self.columns, id: \.self) { _ in
                        RoundedRectangle(cornerRadius: 8)
                            .fill(JellyCastColors.surface)
                            .aspectRatio(2 / 3, contentMode: .fit)
                    }
                }
            }
            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .clipped()
    }
}

#Preview {
    NavigationStack {
        LibraryScreen(store: LibraryStore(session: .preview, snapshot: .preview), search: SearchModel())
    }
    .environment(AppNavigation())
    .preferredColorScheme(.dark)
}
