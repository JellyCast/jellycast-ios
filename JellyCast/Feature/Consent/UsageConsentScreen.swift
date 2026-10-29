import SwiftUI

/// Asked once, before anything else: may JellyCast count this device? Both answers are the same
/// size and weight, and the app works the same either way.
struct UsageConsentScreen: View {
    let onChoose: (UsageStatistics.Choice) -> Void

    private static let maxWidth: CGFloat = 520
    private static let markSize: CGFloat = 56

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    BrandMark(drawProgress: 1)
                        .frame(width: Self.markSize, height: Self.markSize)
                    Text("Help keep JellyCast free")
                        .font(.title.bold())
                        .foregroundStyle(JellyCastColors.text)
                    Text("""
                        JellyCast is free. To find advertisers, we'd like to count how many devices \
                        use the app in each country.
                        """)
                        .foregroundStyle(JellyCastColors.text)
                    UsageStatisticsDetails()
                }
                .frame(maxWidth: Self.maxWidth, alignment: .leading)
                .padding(.horizontal, 24)
                .padding(.vertical, 32)
                .frame(maxWidth: .infinity)
            }
            .scrollBounceBehavior(.basedOnSize)
            HStack(spacing: 12) {
                ChoiceButton(title: "Don't allow") { onChoose(.declined) }
                ChoiceButton(title: "Allow") { onChoose(.allowed) }
            }
            .frame(maxWidth: Self.maxWidth)
            .padding(.horizontal, 24)
            .padding(.bottom, 16)
        }
        .background(JellyCastColors.background)
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
            Point(systemImage: "globe.europe.africa", text: """
                The country comes from your internet address, which is never stored.
                """)
            Point(systemImage: "chart.bar", text: """
                Advertisers only see totals per country. The details are deleted after 13 months.
                """)
            Point(systemImage: "rectangle.on.rectangle", text: """
                JellyCast may show an ad now and then, chosen only by your country. That doesn't \
                depend on what you choose here.
                """)
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

private struct ChoiceButton: View {
    let title: LocalizedStringKey
    let action: () -> Void

    private static let height: CGFloat = 52

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.headline)
                .foregroundStyle(JellyCastColors.text)
                .lineLimit(1)
                .frame(maxWidth: .infinity, minHeight: Self.height)
                .background(JellyCastColors.rail, in: .capsule)
                .contentShape(.capsule)
        }
        .buttonStyle(PressedOpacityButtonStyle())
    }
}

#Preview {
    UsageConsentScreen { _ in }
}
