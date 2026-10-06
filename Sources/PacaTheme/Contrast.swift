import Foundation

/// An sRGB color with WCAG 2.x contrast math.
public struct RGB: Hashable, Sendable, CustomStringConvertible {
    public var r: Double
    public var g: Double
    public var b: Double

    public init(r: Double, g: Double, b: Double) {
        self.r = r
        self.g = g
        self.b = b
    }

    public init(hex: UInt32) {
        r = Double((hex >> 16) & 0xFF) / 255
        g = Double((hex >> 8) & 0xFF) / 255
        b = Double(hex & 0xFF) / 255
    }

    public static let white = RGB(r: 1, g: 1, b: 1)
    public static let black = RGB(r: 0, g: 0, b: 0)

    public var hex: UInt32 {
        func byte(_ v: Double) -> UInt32 { UInt32((min(max(v, 0), 1) * 255).rounded()) }
        return byte(r) << 16 | byte(g) << 8 | byte(b)
    }

    public var description: String { String(format: "#%06X", hex) }

    /// WCAG relative luminance.
    public var luminance: Double {
        func linear(_ c: Double) -> Double { c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4) }
        return 0.2126 * linear(r) + 0.7152 * linear(g) + 0.0722 * linear(b)
    }

    /// Straight blend in sRGB; `t` = 0 is self, 1 is `other`.
    public func mixed(with other: RGB, _ t: Double) -> RGB {
        RGB(r: r + (other.r - r) * t, g: g + (other.g - g) * t, b: b + (other.b - b) * t)
    }

    /// Self painted at `alpha` over `background`.
    public func composited(over background: RGB, alpha: Double) -> RGB {
        background.mixed(with: self, alpha)
    }

    /// WCAG contrast ratio, 1…21.
    public static func contrast(_ a: RGB, _ b: RGB) -> Double {
        let (hi, lo) = a.luminance > b.luminance ? (a.luminance, b.luminance) : (b.luminance, a.luminance)
        return (hi + 0.05) / (lo + 0.05)
    }

    /// Lowest contrast against any of `backgrounds`.
    public func worstContrast(on backgrounds: [RGB]) -> Double {
        backgrounds.map { RGB.contrast(self, $0) }.min() ?? 21
    }

    /// The smallest move toward `target` (usually white on dark themes, black on light ones)
    /// that reaches `minimum` against every background. Keeps the hue's character where it can.
    public func ensuring(_ minimum: Double, on backgrounds: [RGB], toward target: RGB) -> RGB {
        guard worstContrast(on: backgrounds) < minimum else { return self }
        var low = 0.0, high = 1.0
        for _ in 0..<24 {
            let mid = (low + high) / 2
            if mixed(with: target, mid).worstContrast(on: backgrounds) >= minimum { high = mid } else { low = mid }
        }
        return mixed(with: target, high)
    }
}
