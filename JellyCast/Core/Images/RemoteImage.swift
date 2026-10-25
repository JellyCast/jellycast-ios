import SwiftUI

extension EnvironmentValues {
    @Entry var jellyfinClient: JellyfinClient?
}

/// A server image filling its frame, requested at the frame's width in pixels.
struct RemoteImage: View {
    let ref: ImageRef?
    var type: JellyfinClient.ImageType = .primary
    let width: CGFloat

    @Environment(\.jellyfinClient) private var client
    @Environment(\.displayScale) private var displayScale
    @State private var loaded: (url: URL, image: UIImage)?

    private static let fadeInSeconds = 0.15

    var body: some View {
        let url = imageURL
        let image = loaded.flatMap { $0.url == url ? $0.image : nil }
            ?? url.flatMap(ImagePipeline.shared.cachedImage(for:))
        Rectangle()
            .fill(JellyCastColors.surface)
            .overlay {
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .transition(.opacity)
                }
            }
            .clipped()
            .task(id: url) {
                guard let url, image == nil else { return }
                guard let fetched = await ImagePipeline.shared.image(for: url) else { return }
                withAnimation(.easeOut(duration: Self.fadeInSeconds)) { loaded = (url, fetched) }
            }
            .accessibilityHidden(true)
    }

    private var imageURL: URL? {
        guard let ref, let client else { return nil }
        let pixelWidth = Int((width * displayScale).rounded(.up))
        return client.imageURL(ref, type: type, pixelWidth: pixelWidth)
    }
}
