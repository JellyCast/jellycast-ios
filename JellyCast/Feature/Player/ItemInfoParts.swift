import SwiftUI

struct TechBadges: View {
    let parts: [String]

    private static let rowHeight: CGFloat = 24

    var body: some View {
        HStack(spacing: 6) {
            ForEach(parts, id: \.self) { part in
                Text(part.uppercased())
                    .font(.caption.weight(.bold))
                    .tracking(0.6)
                    .foregroundStyle(JellyCastColors.text)
                    .padding(.horizontal, 8)
                    .frame(height: Self.rowHeight)
                    .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(JellyCastColors.rail, lineWidth: 1))
            }
        }
        .lineLimit(1)
        .frame(height: Self.rowHeight)
    }
}

/// Opens the site's app when it is installed (a universal link), Safari otherwise.
struct ExternalLink: View {
    let source: RatingSource
    let url: URL

    var body: some View {
        Link(destination: url) {
            HStack(spacing: 6) {
                Text(verbatim: source.title).font(.subheadline.weight(.bold))
                Image(systemName: "arrow.up.right").font(.caption.weight(.bold))
                    .foregroundStyle(JellyCastColors.textMuted)
            }
            .foregroundStyle(JellyCastColors.text)
            .padding(.horizontal, 14)
            .frame(height: 34)
            .background(JellyCastColors.surface, in: .capsule)
        }
        .buttonStyle(PressedOpacityButtonStyle())
    }
}
