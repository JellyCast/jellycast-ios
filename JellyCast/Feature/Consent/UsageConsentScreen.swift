import SwiftUI

/// Asked once, before anything else: may JellyCast count this device? Continuing allows it;
/// declining is one tap on the same screen, and the app works the same either way.
struct UsageConsentScreen: View {
    let onChoose: (UsageStatistics.Choice) -> Void

    @State private var showsDetails = false

    private static let maxWidth: CGFloat = 520
    private static let markSize: CGFloat = 56

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    BrandMark(drawProgress: 1)
                        .frame(width: Self.markSize, height: Self.markSize)
                    Text("Statistics")
                        .font(.title.bold())
                        .foregroundStyle(JellyCastColors.text)
                    Text("We count how many devices use JellyCast, per country. Without your name or what you watch.")
                        .foregroundStyle(JellyCastColors.text)
                    moreInformation
                }
                .frame(maxWidth: Self.maxWidth, alignment: .leading)
                .padding(.horizontal, 24)
                .padding(.vertical, 32)
                .frame(maxWidth: .infinity)
            }
            .scrollBounceBehavior(.basedOnSize)
            VStack(spacing: 4) {
                ContinueButton { onChoose(.allowed) }
                Button("Continue without statistics") { onChoose(.declined) }
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(JellyCastColors.textMuted)
                    .frame(minHeight: 44)
            }
            .frame(maxWidth: Self.maxWidth)
            .padding(.horizontal, 24)
            .padding(.bottom, 12)
        }
        .background(JellyCastColors.background)
    }

    private var moreInformation: some View {
        VStack(alignment: .leading, spacing: 16) {
            Button {
                withAnimation(.easeOut(duration: 0.2)) { showsDetails.toggle() }
            } label: {
                HStack(spacing: 6) {
                    Text("More information")
                    Image(systemName: "chevron.down")
                        .font(.footnote.weight(.semibold))
                        .rotationEffect(.degrees(showsDetails ? 180 : 0))
                }
                .font(.subheadline.weight(.medium))
                .foregroundStyle(JellyCastColors.accent)
            }
            .buttonStyle(PressedOpacityButtonStyle())
            if showsDetails {
                UsageStatisticsDetails().transition(.opacity)
            }
        }
    }
}

/// What is sent and what isn't, shared by the first question and Settings.
struct UsageStatisticsDetails: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Point(systemImage: "number", text: """
                When you open the app, it sends a random number made for this app, your country and \
                the hour. Not your name, your server or what you watch.
                """)
            Point(systemImage: "iphone", text: """
                For support it also sends the kind of device, its system version and the app version, \
                such as "iPhone 17, iOS 26, JellyCast 1.0". Not the name of your device.
                """)
            Point(systemImage: "globe.europe.africa", text: """
                The country comes from your internet address, which is never stored.
                """)
            Point(systemImage: "clock", text: "The details are deleted after 13 months.")
            Point(systemImage: "gearshape", text: "You can change this any time in Settings.")
        }
    }

    private struct Point: View {
        let systemImage: String
        let text: LocalizedStringKey

        private static let iconWidth: CGFloat = 24

        var body: some View {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Image(systemName: systemImage)
                    .foregroundStyle(JellyCastColors.accent)
                    .frame(width: Self.iconWidth)
                Text(text)
                    .font(.subheadline)
                    .foregroundStyle(JellyCastColors.textMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

private struct ContinueButton: View {
    let action: () -> Void

    private static let height: CGFloat = 52

    var body: some View {
        Button(action: action) {
            Text("Continue")
                .font(.headline.weight(.bold))
                .foregroundStyle(JellyCastColors.onAccent)
                .frame(maxWidth: .infinity, minHeight: Self.height)
                .background(JellyCastColors.accent, in: .capsule)
                .contentShape(.capsule)
        }
        .buttonStyle(PressedOpacityButtonStyle())
    }
}

#Preview {
    UsageConsentScreen { _ in }
}
