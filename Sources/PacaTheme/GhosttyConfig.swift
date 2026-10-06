import Foundation

/// The parts of Ghostty's effective configuration Paca mirrors so its terminal feels like
/// Ghostty: colors, font, and `text:` keybinds. Read from `ghostty +show-config`, which
/// resolves themes and defaults for us.
public struct GhosttyConfig: Hashable, Sendable {
    public var themeName: String?
    public var background: UInt32?
    public var foreground: UInt32?
    public var cursorColor: UInt32?
    public var selectionBackground: UInt32?
    public var palette: [Int: UInt32] = [:]
    public var fontFamily: String?
    public var fontSize: Double?
    /// `wght` from `font-variation`, for variable fonts.
    public var fontWeight: Double?
    /// What a Ghostty keybind does, for the actions Paca can mirror in a herdr pane.
    public enum KeyAction: Hashable, Sendable {
        case text([UInt8])
        case jumpToPrompt(Int)
        case scrollToTop
        case scrollToBottom
        case scrollPageUp
        case scrollPageDown
    }

    /// Trigger (`super+arrow_up`) → action. Other Ghostty actions (splits, tabs, copy) are
    /// handled by Paca's own UI or don't apply, so they're skipped.
    public var keyActions: [String: KeyAction] = [:]

    /// Trigger → bytes, for `text:` keybinds only.
    public var textKeybinds: [String: [UInt8]] {
        keyActions.compactMapValues { if case .text(let bytes) = $0 { return bytes } else { return nil } }
    }

    /// Ghostty's macOS defaults for the actions above, used when Ghostty isn't installed.
    public static let defaultKeyActions: [String: KeyAction] = [
        "super+arrow_left": .text([0x01]), "super+arrow_right": .text([0x05]),
        "super+backspace": .text([0x15]),
        "super+arrow_up": .jumpToPrompt(-1), "super+arrow_down": .jumpToPrompt(1),
        "super+shift+arrow_up": .jumpToPrompt(-1), "super+shift+arrow_down": .jumpToPrompt(1),
        "super+home": .scrollToTop, "super+end": .scrollToBottom,
        "super+page_up": .scrollPageUp, "super+page_down": .scrollPageDown,
    ]

    public init() {}

    /// Where Ghostty's CLI lives, if installed.
    public static var binary: String? {
        ["/Applications/Ghostty.app/Contents/MacOS/ghostty", "/opt/homebrew/bin/ghostty", "/usr/local/bin/ghostty"]
            .first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    /// Runs `ghostty +show-config` (about 15 ms). Nil when Ghostty isn't installed.
    public static func load() -> GhosttyConfig? {
        guard let binary else { return nil }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: binary)
        process.arguments = ["+show-config"]
        let out = Pipe()
        process.standardOutput = out
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { return nil }
        let data = out.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0, let text = String(data: data, encoding: .utf8) else { return nil }
        return parse(text)
    }

    public static func parse(_ text: String) -> GhosttyConfig {
        var config = GhosttyConfig()
        for raw in text.split(whereSeparator: \.isNewline) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            guard !line.hasPrefix("#"), let eq = line.firstIndex(of: "=") else { continue }
            let key = line[..<eq].trimmingCharacters(in: .whitespaces)
            let value = line[line.index(after: eq)...].trimmingCharacters(in: .whitespaces)
                .trimmingCharacters(in: CharacterSet(charactersIn: "\""))
            switch key {
            case "theme": config.themeName = value
            case "background": config.background = hex(value)
            case "foreground": config.foreground = hex(value)
            case "cursor-color": config.cursorColor = hex(value)
            case "selection-background": config.selectionBackground = hex(value)
            case "palette":
                let parts = value.split(separator: "=", maxSplits: 1)
                if parts.count == 2, let index = Int(parts[0]), let color = hex(String(parts[1])) {
                    config.palette[index] = color
                }
            case "font-family":
                if config.fontFamily == nil, !value.isEmpty { config.fontFamily = value }
            case "font-size": config.fontSize = Double(value)
            case "font-variation":
                for axis in value.split(separator: ",") {
                    let kv = axis.split(separator: "=")
                    if kv.count == 2, kv[0].trimmingCharacters(in: .whitespaces) == "wght" {
                        config.fontWeight = Double(kv[1].trimmingCharacters(in: .whitespaces))
                    }
                }
            case "keybind":
                // `trigger=action[:param]`; a text payload may itself contain "=".
                guard let eq = value.firstIndex(of: "=") else { continue }
                let trigger = String(value[..<eq]).lowercased()
                let action = String(value[value.index(after: eq)...])
                if let parsed = keyAction(action) { config.keyActions[trigger] = parsed }
            default: break
            }
        }
        return config
    }

    static func keyAction(_ action: String) -> KeyAction? {
        if action.hasPrefix("text:") { return .text(unescape(String(action.dropFirst(5)))) }
        if action.hasPrefix("jump_to_prompt:"), let n = Int(action.dropFirst("jump_to_prompt:".count)) { return .jumpToPrompt(n) }
        switch action {
        case "scroll_to_top": return .scrollToTop
        case "scroll_to_bottom": return .scrollToBottom
        case "scroll_page_up": return .scrollPageUp
        case "scroll_page_down": return .scrollPageDown
        default: return nil
        }
    }

    static func hex(_ value: String) -> UInt32? {
        let digits = value.hasPrefix("#") ? String(value.dropFirst()) : value
        guard digits.count == 6 else { return nil }
        return UInt32(digits, radix: 16)
    }

    /// Zig-style escapes used by Ghostty's `text:` action. `+show-config` prints the
    /// backslashes doubled, so collapse those first.
    static func unescape(_ raw: String) -> [UInt8] {
        let text = raw.replacingOccurrences(of: "\\\\", with: "\\")
        var bytes: [UInt8] = []
        var chars = Array(text.utf8)[...]
        while let c = chars.popFirst() {
            guard c == UInt8(ascii: "\\"), let next = chars.popFirst() else { bytes.append(c); continue }
            switch next {
            case UInt8(ascii: "n"): bytes.append(0x0A)
            case UInt8(ascii: "r"): bytes.append(0x0D)
            case UInt8(ascii: "t"): bytes.append(0x09)
            case UInt8(ascii: "e"): bytes.append(0x1B)
            case UInt8(ascii: "\\"): bytes.append(0x5C)
            case UInt8(ascii: "x"):
                let digits = chars.prefix(2)
                if digits.count == 2, let value = UInt8(String(decoding: digits, as: UTF8.self), radix: 16) {
                    bytes.append(value)
                    chars = chars.dropFirst(2)
                } else {
                    bytes.append(contentsOf: [0x5C, next])
                }
            default: bytes.append(contentsOf: [0x5C, next])
            }
        }
        return bytes
    }

    /// Ghostty's colors as a scheme. The terminal gets Ghostty's exact 16 ANSI colors and
    /// cursor; the UI tones (base01–04) are blended from its background and foreground.
    public var scheme: Base16Scheme? {
        guard let bg = background, let fg = foreground, (0..<16).allSatisfy({ palette[$0] != nil }) else { return nil }
        let back = RGB(hex: bg), front = RGB(hex: fg)
        func tone(_ t: Double) -> UInt32 { back.mixed(with: front, t).hex }
        let p = (0..<16).map { palette[$0]! }
        let colors: [UInt32] = [
            bg, tone(0.05), tone(0.12), p[8], tone(0.55), fg, p[7], p[15],
            p[1], RGB(hex: p[1]).mixed(with: RGB(hex: p[3]), 0.5).hex, p[3], p[2], p[6], p[4], p[5],
            RGB(hex: p[1]).mixed(with: back, 0.35).hex,
        ]
        let name = themeName.map { "Ghostty (\($0))" } ?? "Ghostty"
        return Base16Scheme(id: "ghostty", name: name, isDark: back.luminance < 0.4, colors: colors,
                            ansi: p, cursor: cursorColor)
    }
}
