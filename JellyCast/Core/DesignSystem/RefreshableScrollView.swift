import SwiftUI

/// A vertical scroll view whose content runs under the bars, with its own pull-to-refresh: the
/// system refresh control would sit behind the full-bleed image at the top. The indicator sits in
/// the navigation bar; while refreshing, the content stays pushed down below it.
struct RefreshableScrollView<Content: View>: View {
    let action: () async -> Void
    @ViewBuilder let content: Content

    @State private var pullDistance: CGFloat = 0
    @State private var isRefreshing = false
    @State private var topInset: CGFloat = 0

    private static var indicatorSize: CGFloat { 36 }
    private static var indicatorBottomSpacing: CGFloat { 8 }
    private static var minimumRefreshDuration: Duration { .milliseconds(600) }

    private var pullProgress: Double {
        guard topInset > 0 else { return 0 }
        return min(pullDistance / topInset, 1)
    }

    var body: some View {
        ScrollView {
            content.padding(.top, isRefreshing ? topInset : 0)
        }
        .onScrollGeometryChange(for: CGFloat.self) { geometry in
            max(0, -(geometry.contentOffset.y + geometry.contentInsets.top))
        } action: { _, distance in
            pullDistance = distance
        }
        .onScrollPhaseChange { oldPhase, newPhase in
            if oldPhase == .interacting, newPhase != .interacting, pullProgress >= 1 { refresh() }
        }
        .overlay(alignment: .top) {
            PullToRefreshIndicator(progress: pullProgress, isRefreshing: isRefreshing)
                .frame(width: Self.indicatorSize, height: Self.indicatorSize)
                .padding(.top, topInset - Self.indicatorSize - Self.indicatorBottomSpacing)
                .allowsHitTesting(false)
        }
        .sensoryFeedback(.impact(weight: .light), trigger: pullProgress >= 1) { _, reached in
            reached
        }
        .ignoresSafeArea(edges: .top)
        .onGeometryChange(for: CGFloat.self) { $0.safeAreaInsets.top } action: { topInset = $0 }
    }

    private func refresh() {
        guard !isRefreshing else { return }
        withAnimation(.snappy) { isRefreshing = true }
        Task {
            async let minimumDuration: Void? = try? await Task.sleep(
                for: Self.minimumRefreshDuration
            )
            await action()
            _ = await minimumDuration
            withAnimation(.snappy) { isRefreshing = false }
        }
    }
}

private struct PullToRefreshIndicator: View {
    let progress: Double
    let isRefreshing: Bool

    private static let fullTurnDegrees = 270.0

    var body: some View {
        ZStack {
            if isRefreshing {
                ProgressView().tint(JellyCastColors.text)
            } else {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(progress >= 1 ? JellyCastColors.accent : JellyCastColors.text)
                    .rotationEffect(.degrees(progress * Self.fullTurnDegrees))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .glassEffect(.regular, in: .circle)
        .scaleEffect(isRefreshing ? 1 : 0.6 + 0.4 * progress)
        .opacity(isRefreshing ? 1 : progress)
        .animation(.snappy, value: progress >= 1)
    }
}

#Preview {
    RefreshableScrollView {
        try? await Task.sleep(for: .seconds(1))
    } content: {
        VStack(spacing: 12) {
            Rectangle().fill(JellyCastColors.accent).frame(height: 300)
            ForEach(0..<8) { _ in
                RoundedRectangle(cornerRadius: 10).fill(JellyCastColors.surface).frame(height: 80)
            }
        }
    }
    .background(JellyCastColors.background)
}
