import SwiftUI

enum JellyCastColors {
    static let background = Color(hex: 0x0E0E0F)
    static let surface = Color(hex: 0x1A1A1C)
    static let rail = Color(hex: 0x2A2A2E)
    static let text = Color(hex: 0xECE9E4)
    static let textMuted = Color(hex: 0xA3A09A)

    static let neonBlue = Color(hex: 0x7FC8FF)
    static let neonWhite = Color(hex: 0xF2F6FF)
    static let neonPurple = Color(hex: 0x9B6BFF)
    static let neonPink = Color(hex: 0xFF6EC7)

    static let progressStart = Color(hex: 0x8FB8D8)
    static let progressMid = Color(hex: 0x9A88D0)
    static let progressEnd = Color(hex: 0xC584B0)

    static let accent = Color(hex: 0xB9A6F2)
    static let onAccent = Color(hex: 0x1A1206)
    static let primaryContainer = Color(hex: 0x16161B)
}

extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: opacity
        )
    }
}
