import SwiftUI

/// The top of a movie or series detail: the backdrop from the top edge of the screen, fading
/// into the background, with the logo centered over its bottom edge.
struct DetailHero<Overlay: View>: View {
    let backdrop: ImageRef?
    let logo: ImageRef?
    let title: String
    @ViewBuilder var overlay: Overlay

    @Environment(\.layout) private var layout

    var body: some View {
        let topInset = Self.statusBarHeight
        let logoSize = layout.heroLogoSize
        HeroFrame(topInset: topInset) {
            Color.clear
        }
        .overlay {
            GeometryReader { proxy in
                RemoteImage(ref: backdrop, type: .backdrop, width: proxy.size.width)
            }
            LinearGradient(
                stops: [
                    .init(color: JellyCastColors.background.opacity(0.45), location: 0),
                    .init(color: JellyCastColors.background.opacity(0), location: 0.3),
                    .init(color: JellyCastColors.background.opacity(0), location: 0.5),
                    .init(color: JellyCastColors.background.opacity(0.75), location: 0.8),
                    .init(color: JellyCastColors.background, location: 1),
                ],
                startPoint: .top, endPoint: .bottom
            )
            overlay.padding(.top, topInset)
        }
        .overlay(alignment: .bottom) {
            ItemLogo(ref: logo, title: title, width: logoSize.width)
                .frame(maxWidth: logoSize.width, maxHeight: logoSize.height)
                .padding(.horizontal, layout.margin)
                .offset(y: logoSize.height / 2)
        }
        .padding(.bottom, logoSize.height / 2)
    }

    /// The scroll view under the hero ignores the safe area, so the inset comes from the window.
    private static var statusBarHeight: CGFloat {
        keyWindow?.safeAreaInsets.top ?? 0
    }

    fileprivate static var keyWindow: UIWindow? {
        UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first?.keyWindow
    }
}

/// The full width, 16:9 below the status bar, but never taller than part of the window: on the
/// iPad in landscape a 16:9 backdrop would push everything else off screen.
private struct HeroFrame: Layout {
    let topInset: CGFloat

    private static let imageAspectRatio: CGFloat = 16 / 9
    private static let maxWindowFraction: CGFloat = 0.55

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 0
        let natural = width / Self.imageAspectRatio + topInset
        let windowHeight = DetailHero<EmptyView>.keyWindow?.bounds.height ?? .infinity
        return CGSize(width: width, height: min(natural, windowHeight * Self.maxWindowFraction))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for subview in subviews { subview.place(at: bounds.origin, proposal: ProposedViewSize(bounds.size)) }
    }
}

/// The round play button over a hero's backdrop with, while in progress, the progress under it.
struct HeroPlayButton: View {
    let playable: Playable
    /// What the button plays, such as "Continue · S2 · E3", under it.
    var caption: String?
    let onPlay: () -> Void

    private static let buttonSize: CGFloat = 76
    private static let iconSize: CGFloat = 28
    private static let progressWidth: CGFloat = 96

    var body: some View {
        VStack(spacing: 12) {
            Button(action: onPlay) {
                Image(systemName: "play.fill")
                    .font(.system(size: Self.iconSize, weight: .semibold))
                    .foregroundStyle(JellyCastColors.text)
                    .offset(x: Self.iconSize * 0.08)
                    .frame(width: Self.buttonSize, height: Self.buttonSize)
                    .background(.black.opacity(0.25), in: .circle)
                    .overlay(Circle().strokeBorder(JellyCastColors.text.opacity(0.85), lineWidth: 1.5))
                    .contentShape(.circle)
            }
            .buttonStyle(PressedOpacityButtonStyle())
            .accessibilityLabel(playable.watch.isInProgress ? "Continue" : "Play")
            if let progress = playable.progress {
                WatchProgressBar(progress: progress, height: 3, track: JellyCastColors.text.opacity(0.3))
                    .frame(width: Self.progressWidth)
            }
            if let caption {
                Text(caption)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(JellyCastColors.text)
                    .shadow(color: .black.opacity(0.6), radius: 4)
            }
        }
    }
}

extension DetailHero where Overlay == EmptyView {
    init(backdrop: ImageRef?, logo: ImageRef?, title: String) {
        self.init(backdrop: backdrop, logo: logo, title: title) { EmptyView() }
    }
}

/// The logo of a movie or series, fitted in its frame; the title when there is none.
struct ItemLogo: View {
    let ref: ImageRef?
    let title: String
    let width: CGFloat

    @Environment(\.jellyfinClient) private var client
    @Environment(\.displayScale) private var displayScale
    @State private var loaded: (url: URL, image: UIImage?)?

    var body: some View {
        let url = imageURL
        let cached = url.flatMap(ImagePipeline.shared.cachedImage(for:))
        let result = loaded.flatMap { $0.url == url ? $0 : nil }
        Group {
            if let image = cached ?? result?.image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .accessibilityLabel(title)
            } else if url == nil || result != nil {
                Text(title)
                    .font(.system(size: 34, weight: .heavy))
                    .foregroundStyle(JellyCastColors.text)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.6)
            } else {
                Color.clear
            }
        }
        .task(id: url) {
            guard let url, cached == nil else { return }
            let fetched = await ImagePipeline.shared.image(for: url)
            withAnimation(.easeOut(duration: 0.15)) { loaded = (url, fetched) }
        }
    }

    private var imageURL: URL? {
        guard let ref, let client else { return nil }
        return client.imageURL(ref, type: .logo, pixelWidth: Int((width * displayScale).rounded(.up)))
    }
}

#Preview {
    ScrollView {
        DetailHero(backdrop: nil, logo: nil, title: "Interstellar")
    }
    .ignoresSafeArea(edges: .top)
    .background(JellyCastColors.background)
}
