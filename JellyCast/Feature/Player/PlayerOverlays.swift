import SwiftUI

/// Before the first frame: a spinner, or the countdown while loading ahead on a slow connection.
struct StartOverlay: View {
    let session: PlayerSession

    @State private var initialSecondsLeft: Int?

    private static let ringSize: CGFloat = 72

    var body: some View {
        ZStack {
            Color.black
            if case .loadingAhead(let secondsLeft, let connection, let peak) = session.startPhase {
                ViewThatFits(in: .vertical) {
                    HStack(spacing: 24) {
                        ring(secondsLeft: secondsLeft)
                        VStack(alignment: .leading, spacing: 8) {
                            startsIn(secondsLeft)
                            explanation(connection: connection, peak: peak)
                            startNow
                        }
                        .frame(maxWidth: 420, alignment: .leading)
                    }
                    HStack(spacing: 18) {
                        ring(secondsLeft: secondsLeft)
                        VStack(alignment: .leading, spacing: 8) {
                            startsIn(secondsLeft)
                            startNow
                        }
                    }
                }
                .padding(20)
                .onAppear { initialSecondsLeft = initialSecondsLeft ?? secondsLeft }
            } else {
                ProgressView().tint(JellyCastColors.text).controlSize(.large)
            }
        }
    }

    private func startsIn(_ secondsLeft: Int) -> some View {
        Text("Starts in \(Self.clock(secondsLeft))")
            .font(.title3.bold())
            .foregroundStyle(JellyCastColors.text)
    }

    private func explanation(connection: Int, peak: Int) -> some View {
        Text("""
            The Wi-Fi now does \(connection) Mbit/s and this file peaks at \(peak). \
            Loading ahead first, then it plays without stalling.
            """)
            .font(.subheadline)
            .foregroundStyle(JellyCastColors.textMuted)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var startNow: some View {
        Button("Start now", action: session.startNow).buttonStyle(.glass)
    }

    private func ring(secondsLeft: Int) -> some View {
        let total = Double(max(initialSecondsLeft ?? secondsLeft, 1))
        let done = 1 - Double(secondsLeft) / total
        return ZStack {
            Circle().stroke(JellyCastColors.text.opacity(0.2), lineWidth: 4)
            Circle()
                .trim(from: 0, to: max(0.02, done))
                .stroke(JellyCastColors.accent, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.linear(duration: 0.5), value: done)
            Text(Self.clock(secondsLeft))
                .font(.headline.monospacedDigit())
                .foregroundStyle(JellyCastColors.text)
        }
        .frame(width: Self.ringSize, height: Self.ringSize)
    }

    private static func clock(_ seconds: Int) -> String {
        String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}

/// While the engine waits for data and the controls are hidden; with the controls showing, the
/// play button turns into the spinner instead.
struct StallIndicator: View {
    var body: some View {
        VStack(spacing: 10) {
            ProgressView().tint(JellyCastColors.text).controlSize(.large)
            Text("Waiting for the connection")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(JellyCastColors.text)
        }
        .shadow(color: .black.opacity(0.6), radius: 4)
        .accessibilityElement(children: .combine)
    }
}

/// Why the item does not play, a retry, and the server transcode when the original won't play here.
struct PlayerErrorView: View {
    let message: String
    let session: PlayerSession

    var body: some View {
        ZStack {
            Color.black
            VStack(spacing: 14) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.title2)
                    .foregroundStyle(JellyCastColors.textMuted)
                Text(message)
                    .font(.subheadline)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(JellyCastColors.text)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 10) {
                    Button("Try again") { Task { await session.load() } }
                        .buttonStyle(.glass)
                    if let level = session.serverTranscodeLevel {
                        Button("Play via the server · \(level.shortName)") {
                            Task { await session.playThroughServer() }
                        }
                        .buttonStyle(.glass)
                    }
                }
            }
            .frame(maxWidth: 420)
            .padding(20)
        }
    }
}
