import SwiftUI

/// Columns, gaps and image sizes of the Home grid for one container size.
struct HomeGridMetrics {
    let columns: Int
    let margin: CGFloat
    let columnGap: CGFloat
    let rowGap: CGFloat
    let contentWidth: CGFloat
    let isPhone: Bool

    private static let imageHeightPerWidth: CGFloat = 9 / 16

    init(containerSize: CGSize, isRegular: Bool) {
        let isLandscape = isRegular && containerSize.width > containerSize.height
        isPhone = !isRegular
        columns = isLandscape ? 3 : 2
        margin = isRegular ? 32 : 20
        columnGap = isLandscape ? 21 : (isRegular ? 20 : 12)
        rowGap = isRegular ? 26 : 20
        contentWidth = max(0, containerSize.width - 2 * margin)
    }

    var smallStyle: HomeTileStyle { HomeTileStyle(isFeatured: false, isPhone: isPhone) }
    var featuredStyle: HomeTileStyle { HomeTileStyle(isFeatured: true, isPhone: isPhone) }

    var columnWidth: CGFloat {
        ((contentWidth - CGFloat(columns - 1) * columnGap) / CGFloat(columns)).rounded(.down)
    }

    var smallImageHeight: CGFloat { (columnWidth * Self.imageHeightPerWidth).rounded() }

    /// With three columns the featured tile spans two of them and two rows, beside two tiles.
    var tilesBesideFeatured: Int { columns == 3 ? 2 : 0 }

    var featuredWidth: CGFloat {
        tilesBesideFeatured > 0 ? 2 * columnWidth + columnGap : contentWidth
    }

    /// Beside two stacked tiles the image has no height of its own: `FeaturedRowLayout` gives
    /// the tile the height that lines its meta line up with the lower stacked tile's.
    var featuredImageHeight: CGFloat? {
        tilesBesideFeatured > 0 ? nil : (featuredWidth * Self.imageHeightPerWidth).rounded()
    }
}

/// The width of a tile and the height of its image; `nil` fills the height the grid proposes.
struct HomeTileSize {
    let width: CGFloat
    let imageHeight: CGFloat?
}

/// The featured tile first, then rows of equal tiles; lazy, so a long list stays smooth.
struct HomeGrid<Item: Identifiable, Tile: View, Overlay: View>: View {
    let items: [Item]
    let metrics: HomeGridMetrics
    @ViewBuilder let tile: (Item, HomeTileSize, HomeTileStyle) -> Tile
    @ViewBuilder let featuredOverlay: () -> Overlay

    var body: some View {
        LazyVStack(alignment: .leading, spacing: metrics.rowGap) {
            if let featured = items.first {
                if besideFeatured.isEmpty {
                    featuredTile(featured)
                } else {
                    FeaturedRowLayout(spacing: metrics.columnGap) {
                        featuredTile(featured)
                        VStack(alignment: .leading, spacing: metrics.rowGap) {
                            ForEach(besideFeatured) { smallTile($0) }
                        }
                    }
                }
            }
            ForEach(rows) { row in
                HStack(alignment: .top, spacing: metrics.columnGap) {
                    ForEach(row.items) { smallTile($0) }
                }
            }
        }
        .padding(.horizontal, metrics.margin)
    }

    private func featuredTile(_ item: Item) -> some View {
        tile(
            item, HomeTileSize(width: metrics.featuredWidth, imageHeight: metrics.featuredImageHeight),
            metrics.featuredStyle
        )
        .overlay(alignment: .topTrailing) { featuredOverlay() }
    }

    private func smallTile(_ item: Item) -> some View {
        tile(
            item, HomeTileSize(width: metrics.columnWidth, imageHeight: metrics.smallImageHeight),
            metrics.smallStyle
        )
    }

    private var besideFeatured: [Item] {
        Array(items.dropFirst().prefix(metrics.tilesBesideFeatured))
    }

    private var rows: [Row] {
        let rest = Array(items.dropFirst(1 + metrics.tilesBesideFeatured))
        return stride(from: 0, to: rest.count, by: metrics.columns).map { start in
            Row(items: Array(rest[start..<min(start + metrics.columns, rest.count)]))
        }
    }

    private struct Row: Identifiable {
        let items: [Item]

        var id: Item.ID? { items.first?.id }
    }
}

/// The featured tile beside the stacked column, as tall as it takes for both last text lines
/// to share a baseline: the featured meta uses a larger font, so equal bottoms would not.
private struct FeaturedRowLayout: Layout {
    let spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let sizes = measure(subviews)
        return CGSize(
            width: sizes.featured.width + spacing + sizes.stacked.width,
            height: max(sizes.featured.height, sizes.stacked.height)
        )
    }

    func placeSubviews(
        in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()
    ) {
        guard subviews.count == 2 else { return }
        let sizes = measure(subviews)
        subviews[0].place(at: bounds.origin, proposal: ProposedViewSize(sizes.featured))
        subviews[1].place(
            at: CGPoint(x: bounds.minX + sizes.featured.width + spacing, y: bounds.minY),
            proposal: ProposedViewSize(sizes.stacked)
        )
    }

    private func measure(_ subviews: Subviews) -> (featured: CGSize, stacked: CGSize) {
        guard subviews.count == 2 else { return (.zero, .zero) }
        let stacked = subviews[1].dimensions(in: .unspecified)
        let featuredAtStackedHeight = subviews[0].dimensions(
            in: ProposedViewSize(width: nil, height: stacked.height)
        )
        let featuredBelowBaseline = featuredAtStackedHeight.height
            - featuredAtStackedHeight[VerticalAlignment.lastTextBaseline]
        let featuredHeight = stacked[VerticalAlignment.lastTextBaseline] + featuredBelowBaseline
        return (
            CGSize(width: featuredAtStackedHeight.width, height: featuredHeight),
            CGSize(width: stacked.width, height: stacked.height)
        )
    }
}
