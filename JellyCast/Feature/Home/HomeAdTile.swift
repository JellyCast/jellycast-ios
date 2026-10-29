import SwiftUI

/// A Home tile is a movie or series, or now and then an ad on the place the service chose.
enum HomeEntry: Identifiable {
    case media(HomeItem)
    case ad(AdCampaign)

    var id: String {
        switch self {
        case .media(let item): item.id
        case .ad(let campaign): "ad-\(campaign.id)"
        }
    }
}

extension [HomeItem] {
    /// The ad never takes the first, featured tile; a feed shorter than its place gets it last.
    func entries(with ad: AdCampaign?) -> [HomeEntry] {
        var entries = map(HomeEntry.media)
        guard let ad, !isEmpty else { return entries }
        entries.insert(.ad(ad), at: Swift.min(Swift.max(ad.position ?? 1, 1), count))
        return entries
    }
}

/// Looks like the tiles around it, marked "Ad" with the advertiser, and opens what it is and why.
struct HomeAdTile: View {
    let campaign: AdCampaign
    let country: String?
    let size: HomeTileSize
    let style: HomeTileStyle

    @State private var showsDetails = false

    var body: some View {
        Button { showsDetails = true } label: {
            VStack(alignment: .leading, spacing: 0) {
                AdImage(url: campaign.image, width: size.width)
                    .frame(width: size.width, height: size.imageHeight)
                    .overlay(alignment: .topLeading) {
                        AdLabel(isPhone: style.isPhone).padding(style.isPhone ? 8 : 10)
                    }
                    .clipShape(.rect(cornerRadius: style.cornerRadius))
                Text(campaign.title ?? campaign.advertiser)
                    .font(style.titleFont)
                    .foregroundStyle(JellyCastColors.text)
                    .frame(height: style.titleLineHeight)
                    .padding(.top, style.imageToTitle)
                Text(Format.joined([String(localized: "Ad"), campaign.advertiser]))
                    .font(style.metaFont)
                    .foregroundStyle(JellyCastColors.textMuted)
                    .frame(height: style.metaLineHeight)
                    .padding(.top, style.titleToMeta)
            }
            .lineLimit(1)
            .frame(width: size.width, alignment: .leading)
            .contentShape(.rect)
        }
        .buttonStyle(PressedOpacityButtonStyle())
        .sheet(isPresented: $showsDetails) {
            AdDetailsSheet(campaign: campaign, country: country)
        }
    }
}

private struct AdDetailsSheet: View {
    let campaign: AdCampaign
    let country: String?

    @Environment(\.openURL) private var openURL
    @Environment(\.dismiss) private var dismiss

    private static let imageWidth: CGFloat = 480

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    AdImage(url: campaign.image, width: Self.imageWidth)
                        .aspectRatio(16 / 9, contentMode: .fit)
                        .clipShape(.rect(cornerRadius: 12))
                    VStack(alignment: .leading, spacing: 4) {
                        if let title = campaign.title {
                            Text(title).font(.title3.bold()).foregroundStyle(JellyCastColors.text)
                        }
                        Text(Format.joined([String(localized: "Ad"), campaign.advertiser]))
                            .foregroundStyle(JellyCastColors.textMuted)
                    }
                    if let url = campaign.url {
                        AccentButton(title: String(localized: "Visit website"), systemImage: "safari") {
                            openURL(url)
                        }
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Why am I seeing this?").font(.headline).foregroundStyle(JellyCastColors.text)
                        Text(reason).foregroundStyle(JellyCastColors.textMuted)
                    }
                }
                .padding(20)
            }
            .background(JellyCastColors.background)
            .navigationTitle("Ad")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private var reason: String {
        guard let name = country.flatMap(Locale.current.localizedString(forRegionCode:)) else {
            return String(localized: "JellyCast chooses ads by country only, never by what you watch.")
        }
        return String(localized: """
            JellyCast chooses ads by country only, never by what you watch. You see this one because \
            you're in \(name).
            """)
    }
}

/// An image from the advertiser's address, not from the Jellyfin server.
private struct AdImage: View {
    let url: URL
    let width: CGFloat

    @State private var image: UIImage?

    var body: some View {
        Rectangle()
            .fill(JellyCastColors.surface)
            .overlay {
                if let image = image ?? ImagePipeline.shared.cachedImage(for: url) {
                    Image(uiImage: image).resizable().scaledToFill()
                }
            }
            .clipped()
            .task(id: url) { image = await ImagePipeline.shared.image(for: url) }
            .accessibilityHidden(true)
    }
}

private struct AdLabel: View {
    let isPhone: Bool

    var body: some View {
        Text("Ad")
            .font(.system(size: isPhone ? 10 : 12, weight: .bold))
            .textCase(.uppercase)
            .foregroundStyle(JellyCastColors.text)
            .padding(.horizontal, isPhone ? 5 : 8)
            .frame(height: isPhone ? 16 : 22)
            .background(JellyCastColors.background.opacity(0.8), in: .rect(cornerRadius: isPhone ? 4 : 6))
    }
}
