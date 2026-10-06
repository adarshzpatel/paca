import Foundation

/// Every color Paca draws, derived from a Base16 scheme and then corrected so text and
/// status colors meet WCAG contrast on every surface they sit on.
///
/// Surfaces follow Codex: content darkest, sidebar a step up, chrome a step above that
/// (reversed on light schemes). Corrections only move a color toward white (dark schemes)
/// or black (light schemes), as little as needed, so each theme keeps its character.
public struct ThemePalette: Sendable {
    public struct Minimums: Sendable {
        public var text: Double
        public var secondary: Double
        public var faint: Double
        public var status: Double
        public var terminal: Double

        /// WCAG AA for text, AAA for primary text, 3:1 for hints and icons (1.4.11).
        public static let standard = Minimums(text: 7, secondary: 4.5, faint: 3, status: 4.5, terminal: 4.5)
        /// macOS Accessibility > Display > Increase contrast.
        public static let increased = Minimums(text: 7, secondary: 7, faint: 4.5, status: 7, terminal: 7)
    }

    /// One foreground/background pairing, for reports and tests.
    public struct Check: Sendable {
        public let name: String
        public let original: RGB
        public let adjusted: RGB
        public let backgrounds: [RGB]
        public let minimum: Double

        public var before: Double { original.worstContrast(on: backgrounds) }
        public var after: Double { adjusted.worstContrast(on: backgrounds) }
        public var wasAdjusted: Bool { original != adjusted }
    }

    public let scheme: Base16Scheme
    public let minimums: Minimums

    // Surfaces.
    public let content: RGB
    public let sidebar: RGB
    public let chrome: RGB
    public let card: RGB
    public let cardTab: RGB
    /// A selected sidebar row (washStrong over the sidebar).
    public let selectedRow: RGB

    // Overlay strengths, painted with `text` as the color.
    public let washAlpha: Double
    public let washStrongAlpha: Double
    public let hairlineAlpha: Double

    // Text, strongest to faintest.
    public let text: RGB
    public let text2: RGB
    public let text3: RGB
    public let text4: RGB

    // Accent and status.
    public let accent: RGB
    public let onAccent: RGB
    public let working: RGB
    public let blocked: RGB
    public let done: RGB
    public let danger: RGB

    // Terminal.
    public let terminalBackground: RGB
    public let terminalForeground: RGB
    public let terminalSelection: RGB
    public let caret: RGB
    /// ANSI 0–15, corrected against the terminal background (ANSI 0 stays the background color by convention).
    public let ansi: [RGB]

    public let checks: [Check]

    public init(_ scheme: Base16Scheme, increasedContrast: Bool = false) {
        self.scheme = scheme
        let minimums: Minimums = increasedContrast ? .increased : .standard
        self.minimums = minimums
        func base(_ i: Int) -> RGB { RGB(hex: scheme[i]) }
        let toward: RGB = scheme.isDark ? .white : .black
        var checks: [Check] = []

        content = base(0x00)
        sidebar = base(0x00).mixed(with: base(0x01), 0.6)
        // base01 is the scheme's "lighter background". base02 is sometimes a mid-tone
        // (Solarized), so surfaces only lean on it lightly.
        chrome = base(0x01).mixed(with: base(0x02), 0.15)
        card = base(0x01).mixed(with: base(0x02), 0.3)
        cardTab = base(0x00).mixed(with: base(0x01), 0.5)

        washAlpha = increasedContrast ? 0.08 : 0.05
        washStrongAlpha = increasedContrast ? 0.16 : 0.09
        hairlineAlpha = increasedContrast ? 0.26 : 0.14

        // Correct the primary text first; the selected row is painted with it.
        let surfaces0 = [content, sidebar, chrome, card]
        let text = base(0x05).ensuring(minimums.text, on: surfaces0, toward: toward)
        selectedRow = text.composited(over: sidebar, alpha: washStrongAlpha)
        let surfaces = surfaces0 + [selectedRow]

        func fix(_ name: String, _ color: RGB, _ minimum: Double, on backgrounds: [RGB]) -> RGB {
            let adjusted = color.ensuring(minimum, on: backgrounds, toward: toward)
            checks.append(Check(name: name, original: color, adjusted: adjusted, backgrounds: backgrounds, minimum: minimum))
            return adjusted
        }

        self.text = fix("text", base(0x05), minimums.text, on: surfaces)
        text3 = fix("text3", base(0x04), minimums.secondary, on: surfaces)
        // Halfway between the corrected primary and tertiary, so the hierarchy survives
        // themes where base04 needed a big correction.
        text2 = fix("text2", self.text.mixed(with: text3, 0.5), minimums.secondary, on: surfaces)
        text4 = fix("text4", base(0x03), minimums.faint, on: surfaces)

        accent = fix("accent", base(0x0E), minimums.status, on: surfaces)
        working = fix("working", base(0x0D), minimums.status, on: surfaces)
        blocked = fix("blocked", base(0x0A), minimums.status, on: surfaces)
        done = fix("done", base(0x0B), minimums.status, on: surfaces)
        danger = fix("danger", base(0x08), minimums.status, on: surfaces)

        // Text on accent fills (count badges, send button): whichever reads best.
        let accentFill = accent
        onAccent = [base(0x00), base(0x07), .white, .black].max { RGB.contrast($0, accentFill) < RGB.contrast($1, accentFill) }!
        checks.append(Check(name: "onAccent", original: onAccent, adjusted: onAccent, backgrounds: [accent], minimum: minimums.secondary))

        // Terminal: foreground and every ANSI text color against the terminal background.
        terminalBackground = base(0x00)
        let termBG = [terminalBackground]
        terminalForeground = fix("terminal fg", base(0x05), max(minimums.terminal, minimums.text), on: termBG)
        caret = fix("caret", scheme.cursor.map(RGB.init(hex:)) ?? base(0x0E), 3, on: termBG)
        // Selected terminal text must stay readable: pull the selection toward the background if needed.
        let selection = base(0x02).ensuring(minimums.secondary, on: [terminalForeground], toward: terminalBackground)
        checks.append(Check(name: "terminal selection", original: base(0x02), adjusted: selection,
                            backgrounds: [terminalForeground], minimum: minimums.secondary))
        terminalSelection = selection

        let names = ["black", "red", "green", "yellow", "blue", "magenta", "cyan", "white",
                     "bright black", "bright red", "bright green", "bright yellow",
                     "bright blue", "bright magenta", "bright cyan", "bright white"]
        var ansi = scheme.rawANSI.map(RGB.init(hex:))
        for index in 1..<16 {
            ansi[index] = fix("ansi \(index) \(names[index])", ansi[index], minimums.terminal, on: termBG)
        }
        self.ansi = ansi
        self.checks = checks
    }

    /// Pairings that still miss their minimum after correction (should be empty).
    public var failures: [Check] { checks.filter { $0.after + 0.005 < $0.minimum } }
}
