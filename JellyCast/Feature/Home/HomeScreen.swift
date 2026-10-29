import SwiftUI

/// Home: what to watch now, as one grid of tiles. Built from the cached library, so it shows
/// without the server.
struct HomeScreen: View {
    let store: LibraryStore

    @Environment(AppNavigation.self) private var navigation
    @Environment(\.layout) private var layout
    @State private var containerSize: CGSize = .zero

    private static let topGapPhone: CGFloat = 4
    private static let topGap: CGFloat = 12
    private static let bottomPadding: CGFloat = 24
    private static let profileInset: CGFloat = 10

    var body: some View {
        let feed = store.index.map { $0.homeFeed() } ?? []
        Group {
            if let index = store.index {
                if !feed.isEmpty { grid(feed, index: index) }
            } else if case .failed(let message) = store.syncState {
                ContentErrorView(message: message) { Task { await store.refresh() } }
            } else {
                HomeSkeleton(metrics: metrics, top: topGap)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay(alignment: .topTrailing) {
            if feed.isEmpty { floatingProfileButton }
        }
        .onGeometryChange(for: CGSize.self) { $0.size } action: { containerSize = $0 }
        .background(JellyCastColors.background)
        .overlay(alignment: .top) { SyncProblemOverlay(store: store) }
        .animation(.easeOut(duration: 0.2), value: store.syncFailure)
        .toolbar(layout.isRegular ? .automatic : .hidden, for: .navigationBar)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if layout.isRegular {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { navigation.showsSettings = true } label: {
                        Label("Settings", systemImage: "person")
                    }
                }
            }
        }
    }

    private var metrics: HomeGridMetrics {
        HomeGridMetrics(containerSize: containerSize, isRegular: layout.isRegular)
    }

    private var topGap: CGFloat {
        layout.isRegular ? Self.topGap : Self.topGapPhone
    }

    private func grid(_ feed: [HomeItem], index: LibraryIndex) -> some View {
        RefreshableScrollView(padsSafeAreaTop: true) {
            await store.refresh()
        } content: {
            let ads = AdPlacements.shared
            HomeGrid(items: feed.entries(with: ads.home), metrics: metrics) { entry, size, style in
                switch entry {
                case .media(let item):
                    HomeTile(item: item, index: index, size: size, style: style)
                case .ad(let campaign):
                    HomeAdTile(campaign: campaign, country: ads.country, size: size, style: style)
                }
            } featuredOverlay: {
                if !layout.isRegular { profileButton.padding(Self.profileInset) }
            }
            .padding(.top, topGap)
            .padding(.bottom, Self.bottomPadding)
        }
    }

    private var profileButton: some View {
        GlassCircleButton(systemImage: "person", label: "Settings") { navigation.showsSettings = true }
    }

    /// Where the iPhone shows the profile button while there is no first tile to put it on.
    @ViewBuilder
    private var floatingProfileButton: some View {
        if !layout.isRegular {
            profileButton
                .padding(.top, Self.topGapPhone + Self.profileInset)
                .padding(.trailing, metrics.margin + Self.profileInset)
        }
    }
}

private struct HomeSkeleton: View {
    let metrics: HomeGridMetrics
    let top: CGFloat

    private static let placeholderRows = 3

    var body: some View {
        let count = 1 + metrics.tilesBesideFeatured + Self.placeholderRows * metrics.columns
        HomeGrid(items: Array(0..<count).map(Placeholder.init), metrics: metrics) { _, size, style in
            SkeletonTile(size: size, style: style)
        } featuredOverlay: {
            EmptyView()
        }
        .padding(.top, top)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .clipped()
    }

    private struct Placeholder: Identifiable {
        let id: Int
    }
}

private struct SkeletonTile: View {
    let size: HomeTileSize
    let style: HomeTileStyle

    private static let titleWidthFraction: CGFloat = 0.6
    private static let metaWidthFraction: CGFloat = 0.4

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            RoundedRectangle(cornerRadius: style.cornerRadius)
                .fill(JellyCastColors.surface)
                .frame(width: size.width, height: size.imageHeight)
                .frame(maxHeight: size.imageHeight == nil ? .infinity : nil)
            bar(width: size.width * Self.titleWidthFraction, lineHeight: style.titleLineHeight)
                .padding(.top, style.imageToTitle)
            bar(width: size.width * Self.metaWidthFraction, lineHeight: style.metaLineHeight)
                .padding(.top, style.titleToMeta)
        }
    }

    private func bar(width: CGFloat, lineHeight: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: 4)
            .fill(JellyCastColors.surface)
            .frame(width: width, height: lineHeight * 0.7)
            .frame(height: lineHeight)
    }
}

#Preview {
    NavigationStack {
        HomeScreen(store: LibraryStore(session: .preview, snapshot: .preview))
    }
    .environment(AppNavigation())
    .preferredColorScheme(.dark)
}
