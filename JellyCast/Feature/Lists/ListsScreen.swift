import SwiftUI

/// The user's lists, opened from the Library filter menu.
struct ListsScreen: View {
    let store: LibraryStore

    @Environment(ListsStore.self) private var lists
    @Environment(AppNavigation.self) private var navigation
    @Environment(\.layout) private var layout
    @State private var isNaming = false

    var body: some View {
        Group {
            if !lists.lists.isEmpty {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        subtitle.padding(.bottom, 8)
                        ForEach(lists.lists) { list in
                            Button { navigation.open(.list(id: list.id)) } label: {
                                ListSummaryRow(list: list, progress: ListProgress(list, index: store.index))
                            }
                            .buttonStyle(PressedOpacityButtonStyle())
                        }
                    }
                    .padding(.horizontal, layout.margin)
                    .padding(.bottom, 24)
                }
            } else if case .failed(let message) = lists.loadState {
                ContentErrorView(message: message) { Task { await lists.load() } }
            } else if lists.loadState == .loaded {
                emptyState
            } else {
                ProgressView().tint(JellyCastColors.textMuted).frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(JellyCastColors.background)
        .navigationTitle("Lists")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("New list", systemImage: "plus") { isNaming = true }
            }
        }
        .listNameAlert("New list", isPresented: $isNaming, confirmTitle: "Create") { name in
            Task {
                if let id = await lists.create(name: name, itemIDs: []) { navigation.open(.list(id: id)) }
            }
        }
        .task { await lists.load() }
        .refreshable { await lists.load() }
    }

    private var subtitle: some View {
        Text("Movies and episodes in your own order")
            .font(.subheadline)
            .foregroundStyle(JellyCastColors.textMuted)
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Text("No lists yet")
                .font(.title3.weight(.semibold))
                .foregroundStyle(JellyCastColors.text)
            Text("Make one with + above, or hold a movie, series or episode and choose Add to list…")
                .font(.subheadline)
                .foregroundStyle(JellyCastColors.textMuted)
                .multilineTextAlignment(.center)
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct ListSummaryRow: View {
    let list: UserList
    let progress: ListProgress

    var body: some View {
        HStack(spacing: 14) {
            PosterStack(posters: progress.items.prefix(3).map { ListPoster.of($0.playable) })
            VStack(alignment: .leading, spacing: 3) {
                Text(list.name)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(JellyCastColors.text)
                Text(countLine)
                    .font(.subheadline)
                    .foregroundStyle(JellyCastColors.textMuted)
                statusLine
            }
            .lineLimit(1)
            .frame(maxWidth: .infinity, alignment: .leading)
            Image(systemName: "chevron.right")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(JellyCastColors.textMuted)
                .frame(width: 28)
        }
        .padding(.vertical, 8)
        .contentShape(.rect)
    }

    private var countLine: String {
        let count = String(localized: "\(progress.items.count) titles")
        guard progress.watchedCount > 0 else { return count }
        return Format.joined([count, String(localized: "\(progress.watchedCount) watched")])
    }

    @ViewBuilder
    private var statusLine: some View {
        if progress.items.isEmpty {
            Text("Empty").font(.subheadline).foregroundStyle(JellyCastColors.textMuted)
        } else if let next = progress.next {
            if progress.isStarted {
                Text("Continue with \(ListPoster.title(of: next.playable))")
                    .font(.subheadline)
                    .foregroundStyle(JellyCastColors.accent)
            } else {
                Text("Not started").font(.subheadline).foregroundStyle(JellyCastColors.textMuted)
            }
        } else {
            Text("All watched").font(.subheadline).foregroundStyle(JellyCastColors.textMuted)
        }
    }
}

/// The first posters of a list, shifted over each other.
private struct PosterStack: View {
    let posters: [ImageRef?]

    private static let posterSize = CGSize(width: 50, height: 75)
    private static let shift: CGFloat = 5

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            ForEach(Array(posters.enumerated().reversed()), id: \.offset) { offset, poster in
                RemoteImage(ref: poster, width: Self.posterSize.width)
                    .frame(width: Self.posterSize.width, height: Self.posterSize.height)
                    .clipShape(.rect(cornerRadius: 6))
                    .opacity(offset == 0 ? 1 : 0.7)
                    .offset(x: CGFloat(offset) * Self.shift, y: -CGFloat(offset) * Self.shift)
            }
        }
        .frame(width: 60, height: 90, alignment: .bottomLeading)
    }
}

/// How an item of a list is named and pictured: an episode by its series.
enum ListPoster {
    static func of(_ playable: Playable) -> ImageRef? {
        switch playable {
        case .movie(let movie): movie.poster
        case .episode(let episode): episode.seriesPoster
        }
    }

    static func title(of playable: Playable) -> String {
        switch playable {
        case .movie(let movie): movie.name
        case .episode(let episode): Format.joined([episode.seriesName, Format.seasonEpisode(episode)])
        }
    }
}

extension View {
    /// Asks for a list's name; the button stays off while the name is empty.
    func listNameAlert(
        _ title: LocalizedStringKey, isPresented: Binding<Bool>, initialName: String = "",
        confirmTitle: LocalizedStringKey, onConfirm: @escaping (String) -> Void
    ) -> some View {
        modifier(ListNameAlert(
            title: title, isPresented: isPresented, initialName: initialName,
            confirmTitle: confirmTitle, onConfirm: onConfirm
        ))
    }
}

private struct ListNameAlert: ViewModifier {
    let title: LocalizedStringKey
    @Binding var isPresented: Bool
    let initialName: String
    let confirmTitle: LocalizedStringKey
    let onConfirm: (String) -> Void

    @State private var name = ""

    func body(content: Content) -> some View {
        content
            .alert(title, isPresented: $isPresented) {
                TextField("Name", text: $name)
                Button(confirmTitle) {
                    let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !trimmed.isEmpty { onConfirm(trimmed) }
                }
                .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                Button("Cancel", role: .cancel) {}
            }
            .onChange(of: isPresented) { _, presented in
                if presented { name = initialName }
            }
    }
}

#Preview {
    NavigationStack {
        ListsScreen(store: LibraryStore(session: .preview, snapshot: .preview))
    }
    .environment(ListsStore.preview)
    .environment(AppNavigation())
    .preferredColorScheme(.dark)
}
