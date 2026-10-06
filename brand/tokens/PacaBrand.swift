import AppKit
import SwiftUI

/// Optional brand tokens for adoption by the app. This file is not linked into Paca.
enum PacaBrand {
    static func rgb(_ hex: UInt32) -> NSColor {
        NSColor(srgbRed: CGFloat((hex >> 16) & 255) / 255,
                green: CGFloat((hex >> 8) & 255) / 255,
                blue: CGFloat(hex & 255) / 255, alpha: 1)
    }

    static func adaptive(light: UInt32, dark: UInt32) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            rgb(appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light)
        })
    }

    static let lavender = Color(nsColor: rgb(0xB8A2E8))
    static let mint = Color(nsColor: rgb(0xCDE4D6))
    static let cream = Color(nsColor: rgb(0xFFF5DE))
    static let oat = Color(nsColor: rgb(0xEAD2B2))
    static let ink = Color(nsColor: rgb(0x28262E))
    static let text = adaptive(light: 0x28262E, dark: 0xFFF5DE)
    static let textSecondary = adaptive(light: 0x716879, dark: 0xBCB5C5)
    static let background = adaptive(light: 0xFAF8F4, dark: 0x201E25)
    static let surface = adaptive(light: 0xFFFFFF, dark: 0x28262E)
    static let accent = adaptive(light: 0x69508F, dark: 0xB8A2E8)
    static let working = adaptive(light: 0x285FCC, dark: 0x8CB4FF)
    static let needsInput = adaptive(light: 0x94600E, dark: 0xF0BE6C)
    static let done = adaptive(light: 0x237345, dark: 0x83D8A6)
    static let error = adaptive(light: 0xB83F37, dark: 0xFF9C95)
}
