import SwiftUI

/// Sizes that differ between a compact window (the iPhone, a narrow iPad window) and a regular
/// one (the iPad full screen or a wide window).
struct LayoutMetrics {
    let isRegular: Bool

    var margin: CGFloat { isRegular ? 32 : 20 }
    /// The widest a block of running text gets, so lines stay readable.
    var textMaxWidth: CGFloat { isRegular ? 640 : .infinity }
    var upNextCardWidth: CGFloat { isRegular ? 300 : 220 }
    var posterWidth: CGFloat { isRegular ? 150 : 120 }
    var castImageSize: CGFloat { isRegular ? 88 : 72 }
    var cardSpacing: CGFloat { isRegular ? 16 : 12 }
    var heroLogoSize: CGSize { isRegular ? CGSize(width: 420, height: 120) : CGSize(width: 280, height: 80) }
}

extension EnvironmentValues {
    /// Both size classes: a large iPhone held sideways is regular in width but compact in height,
    /// and keeps the iPhone layout.
    var layout: LayoutMetrics {
        LayoutMetrics(isRegular: horizontalSizeClass == .regular && verticalSizeClass == .regular)
    }
}
