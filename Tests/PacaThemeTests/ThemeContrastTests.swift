import Foundation
import Testing
@testable import PacaTheme

@Test func contrastMathMatchesWCAG() {
    #expect(abs(RGB.contrast(.black, .white) - 21) < 0.001)
    #expect(abs(RGB.contrast(RGB(hex: 0x777777), .white) - 4.48) < 0.01)
}

@Test(arguments: Base16Scheme.builtIn)
func builtInThemesMeetContrastMinimums(scheme: Base16Scheme) {
    for increased in [false, true] {
        let failures = ThemePalette(scheme, increasedContrast: increased).failures
        #expect(failures.isEmpty, "\(scheme.id) increased=\(increased): \(failures.map { "\($0.name) \($0.after)" })")
    }
}

@Test(arguments: Base16Scheme.builtIn)
func textKeepsItsHierarchy(scheme: Base16Scheme) {
    let p = ThemePalette(scheme)
    let ratios = [p.text, p.text2, p.text3, p.text4].map { RGB.contrast($0, p.sidebar) }
    #expect(ratios == ratios.sorted(by: >), "\(scheme.id): \(ratios)")
}

@Test func correctionsOnlyMoveAsFarAsNeeded() {
    // Paca Dark's primary text already passes, so it must not change.
    let p = ThemePalette(.pacaDark)
    #expect(p.text == RGB(hex: Base16Scheme.pacaDark[0x05]))
    // ANSI 0 stays the background color by convention.
    #expect(p.ansi[0] == p.terminalBackground)
}

@Test func loadsClassicAndTintedYAML() throws {
    let classic = """
    scheme: "Classic"
    base00: "181818"
    base01: "282828"
    base02: "383838"
    base03: "585858"
    base04: "b8b8b8"
    base05: "d8d8d8"
    base06: "e8e8e8"
    base07: "f8f8f8"
    base08: "ab4642"
    base09: "dc9656"
    base0A: "f7ca88"
    base0B: "a1b56c"
    base0C: "86c1b9"
    base0D: "7cafc2"
    base0E: "ba8baf"
    base0F: "a16946"
    """
    let a = try #require(Base16Scheme.load(yaml: classic, id: "user:classic"))
    #expect(a.name == "Classic" && a.isDark && a[0x0D] == 0x7CAFC2)

    let palette = classic.split(separator: "\n").dropFirst()
        .map { "  " + $0.replacingOccurrences(of: ": \"", with: ": \"#") }
        .joined(separator: "\n")
    let tinted = "name: \"Tinted\"\nvariant: \"light\"\npalette:\n" + palette
    let b = try #require(Base16Scheme.load(yaml: tinted, id: "user:tinted"))
    #expect(b.name == "Tinted" && !b.isDark && b[0x00] == 0x181818)

    #expect(Base16Scheme.load(yaml: "base00: \"000000\"", id: "user:short") == nil)
}

@Test func readsHerdrThemeConfig() {
    let config = HerdrThemeConfig.parse("""
    [ui]
    name = "not-this-one"

    [theme]
    name = "nord" # comment
    auto_switch = true
    dark_name = "tokyo-night"
    light_name = "catppuccin-latte"

    [theme.custom]
    accent = "#fff"
    """)
    #expect(config.name == "nord")
    #expect(config.active(systemDark: true) == "tokyo-night")
    #expect(config.active(systemDark: false) == "catppuccin-latte")
    #expect(HerdrThemeConfig.parse("").active(systemDark: true) == "catppuccin")
}
