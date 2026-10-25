import SwiftUI

/// The Cast triangle. `drawProgress` (0–1) draws the line in, led by the weld spark; it is
/// animatable, so `withAnimation` drives the draw-in without extra state.
/// `scripts/render-app-icon.swift` renders the app icon from this same drawing.
struct BrandMark: View, Animatable {
    var drawProgress: Double = 1

    var animatableData: Double {
        get { drawProgress }
        set { drawProgress = newValue }
    }

    var body: some View {
        Canvas { context, size in
            let unit = min(size.width, size.height) / BrandGeometry.viewBox
            context.translateBy(
                x: (size.width - BrandGeometry.viewBox * unit) / 2,
                y: (size.height - BrandGeometry.viewBox * unit) / 2
            )
            context.scaleBy(x: unit, y: unit)
            BrandGeometry.draw(in: &context, progress: min(max(drawProgress, 0), 1))
        }
        .accessibilityHidden(true)
    }
}

/// All coordinates are in a 200 × 200 view box.
private enum BrandGeometry {
    static let viewBox: CGFloat = 200
    static let lineWidth: CGFloat = 7
    static let weldTailLength: CGFloat = 37

    /// Starts at the weld spark on the right edge and runs counter-clockwise, so while drawing in
    /// the head arrives from below with its tail underneath, as in the static mark.
    static let outline: [CGPoint] = [
        CGPoint(x: 134, y: 91.6),
        CGPoint(x: 100, y: 30),
        CGPoint(x: 28, y: 160),
        CGPoint(x: 172, y: 160),
        CGPoint(x: 134, y: 91.6),
    ]

    /// Fraction of the line drawn before the signal starts to fade in.
    static let signalStart = 0.6
    static let signalCenter = CGPoint(x: 100, y: 138)
    static let signalDotRadius: CGFloat = 6
    static let signalLineWidth: CGFloat = 6
    static let signalArcRadii: [CGFloat] = [18, 32]

    static let weldGlowRadius: CGFloat = 14
    static let weldCoreSize = CGSize(width: 14, height: 6)
    static let lavender = Color(hex: 0xD9CCFF)

    static let neon = GraphicsContext.Shading.linearGradient(
        Gradient(stops: [
            .init(color: JellyCastColors.neonBlue, location: 0),
            .init(color: JellyCastColors.neonWhite, location: 0.4),
            .init(color: JellyCastColors.neonPurple, location: 0.75),
            .init(color: JellyCastColors.neonPink, location: 1),
        ]),
        startPoint: CGPoint(x: 30, y: 30),
        endPoint: CGPoint(x: 170, y: 165)
    )

    static let outlineLength: CGFloat = zip(outline, outline.dropFirst())
        .reduce(0) { $0 + distance($1.0, $1.1) }

    static func draw(in context: inout GraphicsContext, progress: Double) {
        let head = outlineLength * progress
        drawGlowingStroke(in: context, path: outlinePath(upTo: head))

        let signalOpacity = min(max((progress - signalStart) / (1 - signalStart), 0), 1)
        if signalOpacity > 0 { drawSignal(in: context, opacity: signalOpacity) }

        if progress > 0 {
            drawWeld(
                in: context,
                head: point(at: head),
                tailStart: point(at: max(head - weldTailLength, 0)),
                tangent: tangent(at: head)
            )
        }
    }

    private static func drawGlowingStroke(in context: GraphicsContext, path: Path) {
        for (width, opacity) in [(20.0, 0.06), (13.0, 0.13), (lineWidth, 1.0)] {
            var layer = context
            layer.opacity = opacity
            layer.stroke(path, with: neon, style: roundStroke(width))
        }
    }

    /// A dot with two arcs above it: the "Cast" signal.
    private static func drawSignal(in context: GraphicsContext, opacity: Double) {
        var layer = context
        layer.opacity = opacity
        let dot = CGRect(
            x: signalCenter.x - signalDotRadius,
            y: signalCenter.y - signalDotRadius,
            width: signalDotRadius * 2,
            height: signalDotRadius * 2
        )
        layer.fill(Path(ellipseIn: dot), with: neon)
        for radius in signalArcRadii {
            var arc = Path()
            arc.addArc(
                center: signalCenter,
                radius: radius,
                startAngle: .degrees(180),
                endAngle: .degrees(360),
                clockwise: false
            )
            layer.stroke(arc, with: neon, style: roundStroke(signalLineWidth))
        }
    }

    private static func drawWeld(
        in context: GraphicsContext,
        head: CGPoint,
        tailStart: CGPoint,
        tangent: CGVector
    ) {
        if head != tailStart {
            var tail = Path()
            tail.move(to: tailStart)
            tail.addLine(to: head)
            context.stroke(
                tail,
                with: .linearGradient(
                    Gradient(stops: [
                        .init(color: JellyCastColors.accent.opacity(0), location: 0),
                        .init(color: lavender, location: 0.6),
                        .init(color: .white, location: 1),
                    ]),
                    startPoint: tailStart,
                    endPoint: head
                ),
                style: StrokeStyle(lineWidth: 5, lineCap: .round)
            )
        }

        let glow = CGRect(
            x: head.x - weldGlowRadius,
            y: head.y - weldGlowRadius,
            width: weldGlowRadius * 2,
            height: weldGlowRadius * 2
        )
        context.fill(
            Path(ellipseIn: glow),
            with: .radialGradient(
                Gradient(colors: [
                    JellyCastColors.neonPurple.opacity(0.7),
                    JellyCastColors.neonPurple.opacity(0),
                ]),
                center: head,
                startRadius: 0,
                endRadius: weldGlowRadius
            )
        )

        var core = context
        core.translateBy(x: head.x, y: head.y)
        core.rotate(by: .radians(atan2(tangent.dy, tangent.dx)))
        let coreRect = CGRect(
            x: -weldCoreSize.width / 2,
            y: -weldCoreSize.height / 2,
            width: weldCoreSize.width,
            height: weldCoreSize.height
        )
        core.fill(Path(ellipseIn: coreRect), with: .color(.white))
    }

    private static func outlinePath(upTo length: CGFloat) -> Path {
        var path = Path()
        guard length > 0 else { return path }
        path.move(to: outline[0])
        var remaining = length
        for (start, end) in zip(outline, outline.dropFirst()) {
            let segment = distance(start, end)
            if remaining >= segment {
                path.addLine(to: end)
                remaining -= segment
            } else {
                path.addLine(to: interpolate(start, end, remaining / segment))
                return path
            }
        }
        path.closeSubpath()
        return path
    }

    private static func point(at length: CGFloat) -> CGPoint {
        var remaining = length
        for (start, end) in zip(outline, outline.dropFirst()) {
            let segment = distance(start, end)
            if remaining <= segment { return interpolate(start, end, remaining / segment) }
            remaining -= segment
        }
        return outline[outline.count - 1]
    }

    private static func tangent(at length: CGFloat) -> CGVector {
        var remaining = length
        for (start, end) in zip(outline, outline.dropFirst()) {
            let segment = distance(start, end)
            if remaining <= segment { return direction(start, end) }
            remaining -= segment
        }
        return direction(outline[outline.count - 2], outline[outline.count - 1])
    }

    private static func roundStroke(_ width: CGFloat) -> StrokeStyle {
        StrokeStyle(lineWidth: width, lineCap: .round, lineJoin: .round)
    }

    private static func distance(_ a: CGPoint, _ b: CGPoint) -> CGFloat {
        hypot(b.x - a.x, b.y - a.y)
    }

    private static func interpolate(_ a: CGPoint, _ b: CGPoint, _ t: CGFloat) -> CGPoint {
        CGPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t)
    }

    private static func direction(_ a: CGPoint, _ b: CGPoint) -> CGVector {
        CGVector(dx: b.x - a.x, dy: b.y - a.y)
    }
}

struct BrandWordmark: View {
    var size: CGFloat = 36

    var body: some View {
        let first = Text(verbatim: "Jelly")
            .font(.system(size: size, weight: .bold))
            .foregroundStyle(JellyCastColors.text)
        let second = Text(verbatim: "Cast")
            .font(.system(size: size, weight: .light))
            .foregroundStyle(JellyCastColors.accent)
        Text("\(first)\(second)")
            .tracking(-0.02 * size)
            .accessibilityLabel(Text(verbatim: "JellyCast"))
    }
}

#Preview {
    VStack(spacing: 28) {
        HStack {
            BrandMark().frame(width: 148, height: 148)
            BrandMark(drawProgress: 0.5).frame(width: 148, height: 148)
        }
        BrandWordmark()
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(JellyCastColors.background)
}
