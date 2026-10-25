import SwiftUI

/// Swipe down to close, the same in the player and on the now playing screen: the screen follows
/// the finger and shrinks toward the top while the backdrop fades; a long or fast swipe closes it.
@Observable
final class SwipeToClose {
    private(set) var offset: CGFloat = 0
    private(set) var isClosing = false

    private static let closeDistance: CGFloat = 120
    private static let closeAnimationSeconds = 0.2
    fileprivate static let shrinkAtFullDrag: CGFloat = 0.5

    func progress(height: CGFloat) -> CGFloat {
        min(offset / max(height, 1), 1)
    }

    /// `onClose` runs once the screen has slid away, without animation: the screen is gone already.
    func gesture(height: CGFloat, onClose: @escaping () -> Void) -> some Gesture {
        DragGesture(minimumDistance: 16, coordinateSpace: .global)
            .onChanged { value in
                guard !self.isClosing, value.translation.height > abs(value.translation.width) || self.offset > 0
                else { return }
                self.offset = max(0, value.translation.height)
            }
            .onEnded { value in
                guard self.offset > 0 else { return }
                if self.offset > Self.closeDistance || value.predictedEndTranslation.height > height / 2 {
                    self.close(height: height, then: onClose)
                } else {
                    withAnimation(.spring(duration: 0.25)) { self.offset = 0 }
                }
            }
    }

    private func close(height: CGFloat, then onClose: @escaping () -> Void) {
        withAnimation(.easeIn(duration: Self.closeAnimationSeconds)) {
            offset = height
            isClosing = true
        }
        Task {
            try? await Task.sleep(for: .seconds(Self.closeAnimationSeconds))
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction, onClose)
        }
    }
}

extension View {
    /// Moves and shrinks the screen with the swipe; put it on the content above the backdrop.
    func following(_ swipe: SwipeToClose, height: CGFloat) -> some View {
        scaleEffect(1 - swipe.progress(height: height) * SwipeToClose.shrinkAtFullDrag, anchor: .top)
            .offset(y: swipe.offset)
            .opacity(swipe.isClosing ? 0 : 1)
    }
}

