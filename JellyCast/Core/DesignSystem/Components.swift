import SwiftUI

/// The one filled accent button of a screen: its main action.
struct AccentButton: View {
    let title: String
    var detail: String?
    var systemImage = "play.fill"
    var height: CGFloat = 52
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: systemImage).font(.system(size: 15, weight: .bold))
                Text(title).font(.headline.weight(.bold))
                if let detail {
                    Text(detail).font(.headline.weight(.regular)).opacity(0.7)
                }
            }
            .lineLimit(1)
            .foregroundStyle(JellyCastColors.onAccent)
            .padding(.horizontal, 20)
            .frame(maxWidth: .infinity, minHeight: height)
            .background(JellyCastColors.accent, in: .capsule)
            .contentShape(.capsule)
        }
        .buttonStyle(PressedOpacityButtonStyle())
    }
}

/// A round button on glass, as over a backdrop: back, more, profile.
struct GlassCircleButton: View {
    let systemImage: String
    let label: LocalizedStringKey
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(JellyCastColors.text)
                .frame(width: 44, height: 44)
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.interactive(), in: .circle)
        .accessibilityLabel(label)
    }
}

/// The Back button over a detail page's header while the navigation bar is hidden (iPad
/// landscape): the bar would sit over the tabs beside the header and take their taps.
struct DetailBackButton: View {
    static let top: CGFloat = 8
    static let size: CGFloat = 44
    private static let leading: CGFloat = 16

    @Environment(AppNavigation.self) private var navigation

    var body: some View {
        GlassCircleButton(systemImage: "chevron.left", label: "Back") { navigation.goBack() }
            .padding(.leading, Self.leading)
            .padding(.top, DetailHero<EmptyView>.statusBarHeight + Self.top)
    }
}

/// A round button on the rail color, next to the accent button.
struct RailCircleButton: View {
    let systemImage: String
    let label: LocalizedStringKey
    var size: CGFloat = 52
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(JellyCastColors.text)
                .frame(width: size, height: size)
                .background(JellyCastColors.rail, in: .circle)
        }
        .buttonStyle(PressedOpacityButtonStyle())
        .accessibilityLabel(label)
    }
}

struct PressedOpacityButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.opacity(configuration.isPressed ? 0.7 : 1)
    }
}

/// "Volgende  bezig en volgende aflevering", with an optional trailing link.
struct SectionHeader: View {
    let title: LocalizedStringKey
    var subtitle: LocalizedStringKey?
    var trailing: LocalizedStringKey?
    var onTrailing: (() -> Void)?

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(title).font(.title3.bold()).foregroundStyle(JellyCastColors.text).layoutPriority(1)
            if let subtitle {
                Text(subtitle).font(.subheadline).foregroundStyle(JellyCastColors.textMuted)
            }
            Spacer(minLength: 8)
            if let trailing, let onTrailing {
                Button(trailing, action: onTrailing)
                    .font(.subheadline)
                    .foregroundStyle(JellyCastColors.accent)
            }
        }
        .lineLimit(1)
    }
}

extension View {
    /// Scrolling or tapping outside a text field puts the keyboard away, as in the chat.
    func dismissesKeyboard(_ isFocused: FocusState<Bool>.Binding) -> some View {
        scrollDismissesKeyboard(.interactively)
            .simultaneousGesture(TapGesture().onEnded { isFocused.wrappedValue = false })
    }
}

/// "DEZE WEEK TOEGEVOEGD" above a list.
struct ListSectionLabel: View {
    let text: String

    var body: some View {
        Text(text.uppercased(with: .current))
            .font(.footnote.weight(.semibold))
            .tracking(0.8)
            .foregroundStyle(JellyCastColors.textMuted)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct WatchProgressBar: View {
    let progress: Double
    var height: CGFloat = 4
    var track = JellyCastColors.text.opacity(0.22)

    private static let gradient = [
        JellyCastColors.progressStart, JellyCastColors.progressMid, JellyCastColors.progressEnd,
    ]

    /// The thin bar across the bottom of a still or card image.
    static func onImage(_ progress: Double) -> WatchProgressBar {
        WatchProgressBar(progress: progress, height: 3, track: JellyCastColors.background.opacity(0.7))
    }

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(track)
                Capsule()
                    .fill(LinearGradient(colors: Self.gradient, startPoint: .leading, endPoint: .trailing))
                    .frame(width: proxy.size.width * min(max(progress, 0), 1))
            }
        }
        .frame(height: height)
        .accessibilityValue(Text(progress, format: .percent.precision(.fractionLength(0))))
    }
}

/// A small label on an image, like "NIEUW".
struct ImageBadge: View {
    let text: LocalizedStringKey

    var body: some View {
        Text(text)
            .font(.caption2.weight(.bold))
            .tracking(0.6)
            .textCase(.uppercase)
            .foregroundStyle(JellyCastColors.text)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(JellyCastColors.background.opacity(0.72), in: .capsule)
    }
}

/// The message in place of content that could not load, with a way to retry.
struct ContentErrorView: View {
    let message: String
    let onRetry: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Text(message)
                .multilineTextAlignment(.center)
                .foregroundStyle(JellyCastColors.text)
            Button("Try again", action: onRetry).buttonStyle(.glass)
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#Preview {
    VStack(spacing: 20) {
        AccentButton(title: "Continue · S3 · E4", detail: "18 min left") {}
        HStack {
            GlassCircleButton(systemImage: "chevron.left", label: "Back") {}
            RailCircleButton(systemImage: "checkmark", label: "Mark as watched") {}
            ImageBadge(text: "New")
        }
        SectionHeader(title: "Up next", subtitle: "in progress and next episode", trailing: "All") {}
        ListSectionLabel(text: "Added this week")
        WatchProgressBar(progress: 0.62)
    }
    .padding()
    .background(JellyCastColors.background)
}
