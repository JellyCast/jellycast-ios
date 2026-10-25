// Renders the app icon from the same BrandMark drawing the app uses.
// Run: scripts/render-app-icon.sh

import AppKit
import SwiftUI

private let iconSize: CGFloat = 1024
/// The 200-unit view box at this share makes the triangle as wide as in the Paper artboard "Icoon — B (512)".
private let markShare: CGFloat = 0.82

@main
struct RenderAppIcon {
    @MainActor
    static func main() throws {
        let output = CommandLine.arguments.dropFirst().first ?? "AppIcon.png"
        let icon = BrandMark()
            .frame(width: iconSize * markShare, height: iconSize * markShare)
            .frame(width: iconSize, height: iconSize)
            .background(JellyCastColors.background)

        let renderer = ImageRenderer(content: icon)
        renderer.scale = 1
        renderer.isOpaque = true
        guard let image = renderer.cgImage else {
            throw CocoaError(.fileWriteUnknown)
        }
        let bitmap = NSBitmapImageRep(cgImage: image)
        guard let png = bitmap.representation(using: .png, properties: [:]) else {
            throw CocoaError(.fileWriteUnknown)
        }
        try png.write(to: URL(fileURLWithPath: output))
        print("Wrote \(output)")
    }
}
