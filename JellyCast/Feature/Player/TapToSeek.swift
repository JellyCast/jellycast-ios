import AetherEngine
import SwiftUI

/// Taps on the video: one tap shows or hides the controls, a double tap on the right half jumps
/// forward and on the left half back. Further taps on the same side keep adding, as in YouTube;
/// the seek runs once the taps stop, so a streamed file is asked for one position only.
struct TapToSeekLayer: View {
    @ObservedObject var engine: AetherEngine
    let onSingleTap: () -> Void

    @State private var lastTap: (date: Date, side: SeekSide)?
    @State private var run: SeekRun?
    @State private var seekTask: Task<Void, Never>?

    static let stepSeconds = 10.0
    private static let doubleTapWindow = 0.3
    private static let settleDelay = Duration.milliseconds(650)

    var body: some View {
        GeometryReader { proxy in
            Color.clear
                .contentShape(.rect)
                .gesture(SpatialTapGesture().onEnded { value in
                    tapped(side: value.location.x < proxy.size.width / 2 ? .back : .forward)
                })
                .overlay(alignment: run?.side == .back ? .leading : .trailing) {
                    if let run {
                        SeekBubble(run: run)
                            .frame(width: proxy.size.width * 0.4, height: proxy.size.height)
                            .transition(.opacity)
                            .allowsHitTesting(false)
                    }
                }
        }
        .animation(.easeOut(duration: 0.15), value: run?.side)
        .accessibilityElement()
        .accessibilityLabel("Video")
        .accessibilityAction(named: "Back 10 seconds") { jump(by: -Self.stepSeconds) }
        .accessibilityAction(named: "Forward 10 seconds") { jump(by: Self.stepSeconds) }
    }

    private func jump(by seconds: Double) {
        let target = min(max(0, engine.clock.currentTime + seconds), engine.duration)
        Task { await engine.seek(to: target) }
    }

    private func tapped(side: SeekSide) {
        let now = Date.now
        if var run, run.side == side {
            run.taps += 1
            self.run = run
            settle()
            return
        }
        // The first tap of a double tap already toggled the controls; the second undoes it.
        if let lastTap, lastTap.side == side, now.timeIntervalSince(lastTap.date) < Self.doubleTapWindow {
            self.lastTap = nil
            onSingleTap()
            run = SeekRun(side: side, startSeconds: engine.clock.currentTime, taps: 1)
            settle()
            return
        }
        lastTap = (now, side)
        onSingleTap()
    }

    private func settle() {
        seekTask?.cancel()
        seekTask = Task {
            try? await Task.sleep(for: Self.settleDelay)
            guard !Task.isCancelled, let run else { return }
            self.run = nil
            await engine.seek(to: min(max(0, run.startSeconds + run.offsetSeconds), engine.duration))
        }
    }
}

enum SeekSide {
    case back, forward
}

struct SeekRun: Equatable {
    let side: SeekSide
    let startSeconds: Double
    var taps: Int

    var offsetSeconds: Double {
        Double(taps) * TapToSeekLayer.stepSeconds * (side == .back ? -1 : 1)
    }
}

/// The half-round light over the side that was tapped, with the seconds it jumps.
private struct SeekBubble: View {
    let run: SeekRun

    private static let shadeOpacity = 0.18

    var body: some View {
        ZStack {
            Ellipse()
                .fill(.white.opacity(Self.shadeOpacity))
                .scaleEffect(x: 2, y: 1.4, anchor: run.side == .back ? .trailing : .leading)
                .clipped()
            VStack(spacing: 6) {
                Image(systemName: run.side == .back ? "backward.fill" : "forward.fill")
                    .font(.system(size: 20, weight: .semibold))
                Text("\(Int(abs(run.offsetSeconds))) s")
                    .font(.footnote.weight(.semibold).monospacedDigit())
            }
            .foregroundStyle(JellyCastColors.text)
            .shadow(color: .black.opacity(0.6), radius: 4)
        }
        .accessibilityElement(children: .combine)
    }
}
