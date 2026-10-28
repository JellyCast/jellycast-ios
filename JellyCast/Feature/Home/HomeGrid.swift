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

    /// Beside two stacked tiles the image fills whatever their height leaves, so the bottoms line up.
    var featuredImageHeight: CGFloat {
        guard tilesBesideFeatured > 0 else { return (featuredWidth * Self.imageHeightPerWidth).rounded() }
        let stackedHeight = 2 * (smallImageHeight + smallStyle.textHeight) + rowGap
        return stackedHeight - featuredStyle.textHeight
    }
}

/// The featured tile first, then rows of equal tiles; lazy, so a long list stays smooth.
struct HomeGrid<Item: Identifiable, Tile: View, Overlay: View>: View {
    let items: [Item]
    let metrics: HomeGridMetrics
    @ViewBuilder let tile: (Item, CGSize, HomeTileStyle) -> Tile
    @ViewBuilder let featuredOverlay: () -> Overlay

    var body: some View {
        LazyVStack(alignment: .leading, spacing: metrics.rowGap) {
            if let featured = items.first {
                HStack(alignment: .top, spacing: metrics.columnGap) {
                    tile(featured, featuredSize, metrics.featuredStyle)
                        .overlay(alignment: .topTrailing) { featuredOverlay() }
                    if !besideFeatured.isEmpty {
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

    private func smallTile(_ item: Item) -> some View {
        tile(item, CGSize(width: metrics.columnWidth, height: metrics.smallImageHeight), metrics.smallStyle)
    }

    private var featuredSize: CGSize {
        CGSize(width: metrics.featuredWidth, height: metrics.featuredImageHeight)
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
