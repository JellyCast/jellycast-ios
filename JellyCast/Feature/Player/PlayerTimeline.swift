import AetherEngine
import SwiftUI

/// The progress line; with its knob showing, dragging anywhere on it scrubs.
struct ScrubBar: View {
    @ObservedObject var engine: AetherEngine
    @Binding var scrubSeconds: Double?
    let showsKnob: Bool
    let bufferedAheadSeconds: Double
    let barHeight: CGFloat
    let onInteraction: () -> Void

    private static let knobSize: CGFloat = 13
    private static let touchHeight: CGFloat = 28
    private static let gradient = [
        JellyCastColors.progressStart, JellyCastColors.progressMid, JellyCastColors.progressEnd,
    ]

    var body: some View {
        GeometryReader { proxy in
            ScrubBarTrack(
                clock: engine.clock, duration: engine.duration, scrubSeconds: scrubSeconds,
                bufferedAheadSeconds: bufferedAheadSeconds, width: proxy.size.width,
                barHeight: barHeight, showsKnob: showsKnob
            )
            .frame(maxHeight: .infinity)
            .contentShape(.rect)
            .gesture(scrub(width: proxy.size.width), isEnabled: showsKnob)
        }
        .frame(height: Self.touchHeight)
        .accessibilityElement()
        .accessibilityLabel("Position")
    }

    private func scrub(width: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                let fraction = min(max(value.location.x / max(width, 1), 0), 1)
                scrubSeconds = fraction * engine.duration
                onInteraction()
            }
            .onEnded { _ in
                guard let target = scrubSeconds else { return }
                Task {
                    await engine.seek(to: target)
                    scrubSeconds = nil
                }
            }
    }

    private struct ScrubBarTrack: View {
        @ObservedObject var clock: PlaybackClock
        let duration: Double
        let scrubSeconds: Double?
        let bufferedAheadSeconds: Double
        let width: CGFloat
        let barHeight: CGFloat
        let showsKnob: Bool

        var body: some View {
            let position = scrubSeconds ?? clock.currentTime
            let fraction = self.fraction(of: position)
            let bufferedFraction = self.fraction(of: clock.currentTime + bufferedAheadSeconds)
            ZStack(alignment: .leading) {
                Capsule().fill(JellyCastColors.text.opacity(0.3))
                Capsule()
                    .fill(JellyCastColors.text.opacity(0.35))
                    .frame(width: width * max(bufferedFraction, fraction))
                Capsule()
                    .fill(LinearGradient(colors: ScrubBar.gradient, startPoint: .leading, endPoint: .trailing))
                    .frame(width: width * fraction)
            }
            .frame(height: barHeight)
            .overlay(alignment: .leading) {
                if showsKnob {
                    Circle()
                        .fill(JellyCastColors.text)
                        .frame(width: ScrubBar.knobSize, height: ScrubBar.knobSize)
                        .offset(x: width * fraction - ScrubBar.knobSize / 2)
                }
            }
        }

        private func fraction(of seconds: Double) -> Double {
            duration > 0 ? min(max(seconds / duration, 0), 1) : 0
        }
    }
}

/// The position and length, and how much is loaded ahead of the position.
struct PlayerTimeLabel: View {
    @ObservedObject var engine: AetherEngine
    let scrubSeconds: Double?
    let bufferedAheadSeconds: Double

    var body: some View {
        TimeText(
            clock: engine.clock, duration: engine.duration, scrubSeconds: scrubSeconds,
            bufferedAheadSeconds: bufferedAheadSeconds
        )
    }

    private struct TimeText: View {
        @ObservedObject var clock: PlaybackClock
        let duration: Double
        let scrubSeconds: Double?
        let bufferedAheadSeconds: Double

        var body: some View {
            HStack(spacing: 4) {
                Text(Self.clockText(scrubSeconds ?? clock.currentTime))
                    .foregroundStyle(JellyCastColors.text)
                Text("/ " + Self.clockText(duration))
                    .foregroundStyle(JellyCastColors.textMuted)
                Text("· \(Self.clockText(bufferedAheadSeconds)) buffered")
                    .foregroundStyle(JellyCastColors.textMuted)
            }
            .font(.footnote.weight(.semibold).monospacedDigit())
        }

        private static func clockText(_ seconds: Double) -> String {
            guard seconds.isFinite, seconds >= 0 else { return "--:--" }
            let total = Int(seconds)
            let hours = total / 3600
            return hours > 0
                ? String(format: "%d:%02d:%02d", hours, (total / 60) % 60, total % 60)
                : String(format: "%d:%02d", total / 60, total % 60)
        }
    }
}
