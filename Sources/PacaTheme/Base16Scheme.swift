import Foundation

/// A Base16 color scheme (https://github.com/tinted-theming/home).
/// base00…base07 run background → foreground, base08…base0F are the accents.
public struct Base16Scheme: Identifiable, Hashable, Sendable {
    public let id: String
    public let name: String
    public let isDark: Bool
    /// Exactly 16 colors, base00 through base0F.
    public let colors: [UInt32]
    /// Exact ANSI 0–15 when the source defines them (Ghostty themes); otherwise derived.
    public let ansiOverride: [UInt32]?
    /// Terminal cursor color when the source defines one.
    public let cursor: UInt32?

    public init(id: String, name: String, isDark: Bool, colors: [UInt32], ansi: [UInt32]? = nil, cursor: UInt32? = nil) {
        self.id = id
        self.name = name
        self.isDark = isDark
        self.colors = colors
        self.ansiOverride = ansi?.count == 16 ? ansi : nil
        self.cursor = cursor
    }

    public subscript(_ index: Int) -> UInt32 { colors[index] }

    /// The 16 ANSI colors, mapped the way base16-shell does it.
    public var rawANSI: [UInt32] {
        if let ansiOverride { return ansiOverride }
        return [0x00, 0x08, 0x0B, 0x0A, 0x0D, 0x0E, 0x0C, 0x05,
         0x03, 0x08, 0x0B, 0x0A, 0x0D, 0x0E, 0x0C, 0x07].map { colors[$0] }
    }
}

extension Base16Scheme {
    private init(_ id: String, _ name: String, dark: Bool, _ colors: [UInt32]) {
        precondition(colors.count == 16, "\(id) needs 16 colors")
        self.init(id: id, name: name, isDark: dark, colors: colors)
    }

    // Paca's own pair, built from brand/tokens/palette.json.
    public static let pacaDark = Base16Scheme("paca-dark", "Paca Dark", dark: true, [
        0x0D0D0D, 0x151515, 0x242424, 0x4E4E52, 0x77777C, 0xEDEDED, 0xF5F5F5, 0xFFFFFF,
        0xFF9C95, 0xF2A97A, 0xF0BE6C, 0x83D8A6, 0x8AD4D4, 0x8CB4FF, 0xB8A2E8, 0xEAD2B2,
    ])
    public static let pacaLight = Base16Scheme("paca-light", "Paca Light", dark: false, [
        0xFAF8F4, 0xF1EEE8, 0xE4E0D8, 0xA7A1AC, 0x716879, 0x28262E, 0x1D1B21, 0x141217,
        0xB83F37, 0xA8551A, 0x94600E, 0x237345, 0x1F7A7A, 0x2F6FEB, 0x69508F, 0x8A6A44,
    ])

    /// Ids match herdr's `[theme] name` values so "Match herdr" can look them up directly.
    public static let builtIn: [Base16Scheme] = [
        pacaDark,
        pacaLight,
        Base16Scheme("catppuccin", "Catppuccin Mocha", dark: true, [
            0x1E1E2E, 0x181825, 0x313244, 0x45475A, 0x585B70, 0xCDD6F4, 0xF5E0DC, 0xB4BEFE,
            0xF38BA8, 0xFAB387, 0xF9E2AF, 0xA6E3A1, 0x94E2D5, 0x89B4FA, 0xCBA6F7, 0xF2CDCD,
        ]),
        Base16Scheme("catppuccin-latte", "Catppuccin Latte", dark: false, [
            0xEFF1F5, 0xE6E9EF, 0xCCD0DA, 0xBCC0CC, 0xACB0BE, 0x4C4F69, 0xDC8A78, 0x7287FD,
            0xD20F39, 0xFE640B, 0xDF8E1D, 0x40A02B, 0x179299, 0x1E66F5, 0x8839EF, 0xDD7878,
        ]),
        Base16Scheme("tokyo-night", "Tokyo Night", dark: true, [
            0x1A1B26, 0x16161E, 0x2F3549, 0x444B6A, 0x787C99, 0xA9B1D6, 0xCBCCD1, 0xD5D6DB,
            0xF7768E, 0xFF9E64, 0xE0AF68, 0x9ECE6A, 0x7DCFFF, 0x7AA2F7, 0xBB9AF7, 0xDB4B4B,
        ]),
        Base16Scheme("dracula", "Dracula", dark: true, [
            0x282A36, 0x343746, 0x44475A, 0x6272A4, 0x9EA8C7, 0xF8F8F2, 0xF0F1F4, 0xFFFFFF,
            0xFF5555, 0xFFB86C, 0xF1FA8C, 0x50FA7B, 0x8BE9FD, 0xBD93F9, 0xFF79C6, 0xA16946,
        ]),
        Base16Scheme("nord", "Nord", dark: true, [
            0x2E3440, 0x3B4252, 0x434C5E, 0x4C566A, 0xD8DEE9, 0xE5E9F0, 0xECEFF4, 0x8FBCBB,
            0xBF616A, 0xD08770, 0xEBCB8B, 0xA3BE8C, 0x88C0D0, 0x81A1C1, 0xB48EAD, 0x5E81AC,
        ]),
        Base16Scheme("gruvbox", "Gruvbox Dark", dark: true, [
            0x282828, 0x3C3836, 0x504945, 0x665C54, 0xBDAE93, 0xD5C4A1, 0xEBDBB2, 0xFBF1C7,
            0xFB4934, 0xFE8019, 0xFABD2F, 0xB8BB26, 0x8EC07C, 0x83A598, 0xD3869B, 0xD65D0E,
        ]),
        Base16Scheme("gruvbox-light", "Gruvbox Light", dark: false, [
            0xFBF1C7, 0xEBDBB2, 0xD5C4A1, 0xBDAE93, 0x665C54, 0x504945, 0x3C3836, 0x282828,
            0x9D0006, 0xAF3A03, 0xB57614, 0x79740E, 0x427B58, 0x076678, 0x8F3F71, 0xD65D0E,
        ]),
        Base16Scheme("one-dark", "One Dark", dark: true, [
            0x282C34, 0x353B45, 0x3E4451, 0x545862, 0x565C64, 0xABB2BF, 0xB6BDCA, 0xC8CCD4,
            0xE06C75, 0xD19A66, 0xE5C07B, 0x98C379, 0x56B6C2, 0x61AFEF, 0xC678DD, 0xBE5046,
        ]),
        Base16Scheme("solarized", "Solarized Dark", dark: true, [
            0x002B36, 0x073642, 0x586E75, 0x657B83, 0x839496, 0x93A1A1, 0xEEE8D5, 0xFDF6E3,
            0xDC322F, 0xCB4B16, 0xB58900, 0x859900, 0x2AA198, 0x268BD2, 0x6C71C4, 0xD33682,
        ]),
        Base16Scheme("solarized-light", "Solarized Light", dark: false, [
            0xFDF6E3, 0xEEE8D5, 0x93A1A1, 0x839496, 0x657B83, 0x586E75, 0x073642, 0x002B36,
            0xDC322F, 0xCB4B16, 0xB58900, 0x859900, 0x2AA198, 0x268BD2, 0x6C71C4, 0xD33682,
        ]),
        Base16Scheme("kanagawa", "Kanagawa", dark: true, [
            0x1F1F28, 0x16161D, 0x223249, 0x54546D, 0x727169, 0xDCD7BA, 0xC8C093, 0x717C7C,
            0xC34043, 0xFFA066, 0xC0A36E, 0x76946A, 0x6A9589, 0x7E9CD8, 0x957FB8, 0xD27E99,
        ]),
        Base16Scheme("rose-pine", "Rosé Pine", dark: true, [
            0x191724, 0x1F1D2E, 0x26233A, 0x6E6A86, 0x908CAA, 0xE0DEF4, 0xE0DEF4, 0x524F67,
            0xEB6F92, 0xF6C177, 0xEBBCBA, 0x31748F, 0x9CCFD8, 0xC4A7E7, 0xF6C177, 0x524F67,
        ]),
        Base16Scheme("vesper", "Vesper", dark: true, [
            0x101010, 0x1C1C1C, 0x282828, 0x505050, 0x8B8B8B, 0xEDEDED, 0xF5F5F5, 0xFFFFFF,
            0xFF8080, 0xFFC799, 0xFFC799, 0x99FFE4, 0x99FFE4, 0xA0C4FF, 0xFFC799, 0xB0896B,
        ]),
    ]

    /// Parses a Base16 YAML file: classic (`base00: "1d1f21"`) or tinted-theming
    /// (`palette:` block plus `variant: dark|light`). Nil if any of the 16 colors is missing.
    public static func load(yaml text: String, id: String) -> Base16Scheme? {
        var values: [String: String] = [:]
        for raw in text.split(whereSeparator: \.isNewline) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            guard !line.hasPrefix("#"), let colon = line.firstIndex(of: ":") else { continue }
            let key = line[..<colon].trimmingCharacters(in: .whitespaces).lowercased()
            // Values may be quoted and may carry a leading "#" ("#1d1f21").
            let value = line[line.index(after: colon)...]
                .trimmingCharacters(in: .whitespaces)
                .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
            values[key] = key.hasPrefix("base0") ? String(value.drop(while: { $0 == "#" }).prefix(6)) : value
        }
        let keys = (0..<16).map { String(format: "base%02X", $0).lowercased() }
        let colors = keys.compactMap { values[$0].flatMap { UInt32($0, radix: 16) } }
        guard colors.count == 16 else { return nil }
        let name = values["name"] ?? values["scheme"] ?? id
        let isDark = values["variant"].map { $0 != "light" } ?? (luminance(colors[0]) < 0.5)
        return Base16Scheme(id: id, name: name, isDark: isDark, colors: colors)
    }

    public static func luminance(_ hex: UInt32) -> Double {
        let r = Double((hex >> 16) & 0xFF) / 255, g = Double((hex >> 8) & 0xFF) / 255, b = Double(hex & 0xFF) / 255
        return 0.2126 * r + 0.7152 * g + 0.0722 * b
    }
}

/// herdr's `[theme]` table from `~/.config/herdr/config.toml`.
public struct HerdrThemeConfig: Equatable, Sendable {
    public var name: String?
    public var autoSwitch = false
    public var darkName: String?
    public var lightName: String?

    public init() {}

    public static var path: String {
        ProcessInfo.processInfo.environment["HERDR_CONFIG_PATH"]
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".config/herdr/config.toml").path
    }

    public static func read() -> HerdrThemeConfig {
        guard let text = try? String(contentsOfFile: path, encoding: .utf8) else { return HerdrThemeConfig() }
        return parse(text)
    }

    public static func parse(_ text: String) -> HerdrThemeConfig {
        var config = HerdrThemeConfig()
        var inTheme = false
        for raw in text.split(whereSeparator: \.isNewline) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("[") { inTheme = line == "[theme]"; continue }
            guard inTheme, !line.hasPrefix("#"), let eq = line.firstIndex(of: "=") else { continue }
            let key = line[..<eq].trimmingCharacters(in: .whitespaces)
            let value = line[line.index(after: eq)...]
                .split(separator: "#", maxSplits: 1).first.map(String.init)?
                .trimmingCharacters(in: .whitespaces)
                .trimmingCharacters(in: CharacterSet(charactersIn: "\"")) ?? ""
            switch key {
            case "name": config.name = value
            case "auto_switch": config.autoSwitch = value == "true"
            case "dark_name": config.darkName = value
            case "light_name": config.lightName = value
            default: break
            }
        }
        return config
    }

    /// The theme name herdr is showing right now. herdr's default is catppuccin.
    public func active(systemDark: Bool) -> String {
        if autoSwitch {
            return (systemDark ? darkName : lightName) ?? (systemDark ? "catppuccin" : "catppuccin-latte")
        }
        return name ?? "catppuccin"
    }
}
