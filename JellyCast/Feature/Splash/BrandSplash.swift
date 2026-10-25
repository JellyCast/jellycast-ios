import SwiftUI

/// Shown once per launch on top of the start screen. The system launch screen has the same
/// background color, so the hand-over is invisible.
struct BrandSplash: View {
    let onFinish: () -> Void

    @State private var drawProgress = 0.0
    @State private var wordmarkOpacity = 0.0

    private static let markSize: CGFloat = 132
    private static let gap: CGFloat = 28
    private static let draw = Duration.milliseconds(600)
    private static let wordmarkDelay = Duration.milliseconds(500)
    private static let wordmarkFade = 0.25
    private static let hold = Duration.milliseconds(250)

    var body: some View {
        VStack(spacing: Self.gap) {
            BrandMark(drawProgress: drawProgress)
                .frame(width: Self.markSize, height: Self.markSize)
            BrandWordmark()
                .opacity(wordmarkOpacity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(JellyCastColors.background)
        .contentShape(.rect)
        .onTapGesture(perform: onFinish)
        .task { await play() }
    }

    private func play() async {
        withAnimation(.timingCurve(0.4, 0, 0.2, 1, duration: Self.draw.seconds)) {
            drawProgress = 1
        }
        try? await Task.sleep(for: Self.wordmarkDelay)
        withAnimation(.linear(duration: Self.wordmarkFade)) { wordmarkOpacity = 1 }
        try? await Task.sleep(for: Self.draw - Self.wordmarkDelay + Self.hold)
        guard !Task.isCancelled else { return }
        onFinish()
    }
}

private extension Duration {
    var seconds: Double {
        Double(components.seconds) + Double(components.attoseconds) / 1e18
    }
}

#Preview {
    BrandSplash(onFinish: {})
}
