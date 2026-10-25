import SwiftUI

/// The rest of the collection and the related movies, as poster grids.
struct RelatedTab: View {
    let collectionTitle: String?
    let collection: [Movie]
    /// Nil while the related movies are still loading.
    let related: [Movie]?
    let onSelect: (Playable) -> Void

    private static let columns = [GridItem(.adaptive(minimum: 110), spacing: 12, alignment: .top)]

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            if !collection.isEmpty {
                section(collectionTitle ?? String(localized: "From the same collection"), collection)
            }
            if let related {
                if !related.isEmpty {
                    section(String(localized: "Related"), related)
                } else if collection.isEmpty {
                    Text("Nothing related in the library.")
                        .foregroundStyle(JellyCastColors.textMuted)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 24)
                }
            } else {
                ProgressView().frame(maxWidth: .infinity).padding(.vertical, 12)
            }
        }
    }

    private func section(_ title: String, _ movies: [Movie]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            ListSectionLabel(text: title)
            LazyVGrid(columns: Self.columns, alignment: .leading, spacing: 18) {
                ForEach(movies) { movie in
                    Button { onSelect(.movie(movie)) } label: { tile(movie) }
                        .buttonStyle(PressedOpacityButtonStyle())
                }
            }
        }
    }

    private func tile(_ movie: Movie) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Color.clear
                .aspectRatio(2 / 3, contentMode: .fit)
                .overlay {
                    GeometryReader { proxy in RemoteImage(ref: movie.poster, width: proxy.size.width) }
                }
                .clipShape(.rect(cornerRadius: 8))
            Text(movie.name)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(JellyCastColors.text)
                .lineLimit(3)
                .multilineTextAlignment(.leading)
            if let year = movie.year {
                Text(String(year)).font(.caption).foregroundStyle(JellyCastColors.textMuted)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
