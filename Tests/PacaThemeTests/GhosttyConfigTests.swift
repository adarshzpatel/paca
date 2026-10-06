import Foundation
import Testing
@testable import PacaTheme

@Test func parsesGhosttyShowConfig() throws {
    var lines = """
    theme = ayu
    background = #0b0e14
    foreground = #bfbdb6
    cursor-color = #e6b450
    font-family = IoskeleyMono Nerd Font
    font-family = Fallback Font
    font-size = 14
    font-variation = wght=500
    keybind = super+backspace=text:\\\\x15
    keybind = shift+enter=text:\\\\n
    keybind = ctrl+a=goto_split:left
    keybind = super+shift+arrow_up=jump_to_prompt:-1
    keybind = super+home=scroll_to_top
    """
    for i in 0..<16 { lines += "\npalette = \(i)=#\(String(format: "%06x", 0x101010 * (i % 15) + 1))" }
    let config = GhosttyConfig.parse(lines)
    #expect(config.themeName == "ayu")
    #expect(config.fontFamily == "IoskeleyMono Nerd Font")
    #expect(config.fontSize == 14 && config.fontWeight == 500)
    #expect(config.textKeybinds["super+backspace"] == [0x15])
    #expect(config.textKeybinds["shift+enter"] == [0x0A])
    #expect(config.textKeybinds["ctrl+a"] == nil)
    #expect(config.keyActions["ctrl+a"] == nil)
    #expect(config.keyActions["super+shift+arrow_up"] == .jumpToPrompt(-1))
    #expect(config.keyActions["super+home"] == .scrollToTop)

    let scheme = try #require(config.scheme)
    #expect(scheme.id == "ghostty" && scheme.name == "Ghostty (ayu)" && scheme.isDark)
    #expect(scheme.rawANSI.count == 16 && scheme.rawANSI[1] == config.palette[1])
    #expect(ThemePalette(scheme).failures.isEmpty)
}

@Test func unescapesGhosttyText() {
    #expect(GhosttyConfig.unescape("\\x1b[A") == [0x1B, 0x5B, 0x41])
    #expect(GhosttyConfig.unescape("a\\tb\\\\") == [0x61, 0x09, 0x62, 0x5C])
}
