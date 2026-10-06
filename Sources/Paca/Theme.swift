import AppKit
import HerdrKit
import PacaTheme
import SwiftUI

/// Paca design tokens. Values come from `ThemePalette`, which derives them from the active
/// Base16 scheme and corrects them to meet WCAG contrast (stricter with Increase contrast).
/// The root view is rebuilt when the palette changes (see `Themed`).
enum Theme {
    nonisolated(unsafe) static var palette = ThemePalette(.pacaDark)
    static var current: Base16Scheme { palette.scheme }

    static func rgb(_ hex: UInt32, _ alpha: CGFloat = 1) -> NSColor {
        NSColor(
            srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: alpha
        )
    }

    static func ns(_ color: RGB, _ alpha: Double = 1) -> NSColor {
        NSColor(srgbRed: color.r, green: color.g, blue: color.b, alpha: alpha)
    }

    private static func color(_ color: RGB, _ alpha: Double = 1) -> Color {
        Color(nsColor: ns(color, alpha))
    }

    // Text, strongest to faintest.
    static var text: Color { color(palette.text) }
    static var text2: Color { color(palette.text2) }
    static var text3: Color { color(palette.text3) }
    static var text4: Color { color(palette.text4) }

    // Surfaces.
    static var chromeNS: NSColor { ns(palette.chrome) }
    static var chrome: Color { color(palette.chrome) }
    static var sidebar: Color { color(palette.sidebar) }
    static var content: Color { color(palette.content) }
    static var terminal: Color { color(palette.terminalBackground) }
    static var card: Color { color(palette.card) }
    static var cardTab: Color { color(palette.cardTab) }
    static var wash: Color { color(palette.text, palette.washAlpha) }
    static var washStrong: Color { color(palette.text, palette.washStrongAlpha) }
    static var hairline: Color { color(palette.text, palette.hairlineAlpha) }

    // Accent and status.
    static var accent: Color { color(palette.accent) }
    static var onAccent: Color { color(palette.onAccent) }
    static var working: Color { color(palette.working) }
    static var blocked: Color { color(palette.blocked) }
    static var done: Color { color(palette.done) }
    static var danger: Color { color(palette.danger) }

    /// A workspace's folder and pill color: the one picked in its context menu, or else a stable
    /// hashed pick from the scheme's cyan, magenta, orange and brown. The automatic set avoids
    /// the status colors so a dot can't be mistaken for "working" or "blocked".
    /// `text` raises the contrast floor from 3:1 (dots, icons) to 4.5:1 for small text.
    @MainActor static func workspaceTint(_ id: String, scope: String, text: Bool = false) -> Color {
        let slot = WorkspaceColors.shared.slot(for: id, scope: scope) ?? automaticSlot(id)
        return Color(nsColor: workspaceTintNS(slot: slot, contrast: text ? 4.5 : 3))
    }

    /// A stable color for any key (sessions, machines) from the same automatic set.
    static func hashedTint(_ key: String, text: Bool = false) -> Color {
        Color(nsColor: workspaceTintNS(slot: automaticSlot(key), contrast: text ? 4.5 : 3))
    }

    private static func automaticSlot(_ key: String) -> Int {
        let automatic = [0x0C, 0x0E, 0x09, 0x0F]
        let hash = key.utf8.reduce(UInt32(5381)) { ($0 &<< 5) &+ $0 &+ UInt32($1) }
        return automatic[Int(hash % UInt32(automatic.count))]
    }

    /// A Base16 slot nudged to `contrast` against the app's surfaces.
    static func workspaceTintNS(slot: Int, contrast: Double = 3) -> NSColor {
        let toward: RGB = current.isDark ? .white : .black
        return ns(RGB(hex: current[slot]).ensuring(contrast, on: [palette.chrome, palette.sidebar, palette.content], toward: toward))
    }

    // Brand constants that don't change with the scheme.
    static let mint = Color(nsColor: rgb(0xCDE4D6))
    static let ink = Color(nsColor: rgb(0x28262E))

    static func color(for status: AgentStatus) -> Color {
        switch status {
        case .working: working
        case .blocked: blocked
        case .done: done
        case .idle, .unknown: text4
        }
    }

    /// Space the traffic lights need, after WindowChrome re-centers them in the 40pt top bar.
    static let trafficLightInset: CGFloat = 75

    /// The spacing step for the rail and sidebar: gaps between items and insets from edges
    /// both use it, so horizontal and vertical spacing match.
    static let space: CGFloat = 8
}

extension AgentStatus {
    var title: String? {
        switch self {
        case .working: "Working"
        case .blocked: "Needs input"
        case .done: "Done"
        case .idle, .unknown: nil
        }
    }
}
