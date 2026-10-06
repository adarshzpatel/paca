import AppKit
import CoreText
import Observation
import PacaTheme

/// Which scheme Paca shows. Default follows herdr so the GUI and the TUI look the same.
@MainActor
@Observable
final class ThemeStore {
    static let shared = ThemeStore()
    static let choiceKey = "theme.choice"
    static let matchHerdr = "herdr"
    static let matchSystem = "system"
    static let matchGhostty = "ghostty"
    static let fontKey = "terminal.font"

    private(set) var scheme: Base16Scheme = .pacaDark
    /// macOS Accessibility > Display > Increase contrast. Raises Paca's contrast minimums.
    private(set) var increasedContrast = NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast
    /// Changes whenever the drawn colors change; `Themed` rebuilds views on it.
    var paletteKey: String {
        [scheme.id, increasedContrast ? "contrast" : "", terminalFontChoice, ghostty.map { "\($0.hashValue)" } ?? ""].joined(separator: "|")
    }

    /// Ghostty's effective config, if Ghostty is installed. Re-read when Paca comes forward.
    private(set) var ghostty: GhosttyConfig? = GhosttyConfig.load()

    /// "ghostty" (match Ghostty's font) or "paca" (IBM Plex Mono).
    var terminalFontChoice: String = UserDefaults.standard.string(forKey: ThemeStore.fontKey) ?? "ghostty" {
        didSet { UserDefaults.standard.set(terminalFontChoice, forKey: Self.fontKey) }
    }

    /// The terminal font: Ghostty's family, size and weight when matching Ghostty.
    var terminalFont: NSFont {
        if terminalFontChoice == "ghostty", let g = ghostty, let family = g.fontFamily,
           let font = Self.font(family: family, size: g.fontSize ?? 13, weight: g.fontWeight) {
            return font
        }
        return Brand.terminalFont()
    }

    var terminalFontName: String {
        if terminalFontChoice == "ghostty", let g = ghostty, let family = g.fontFamily {
            return "\(family) \(Int(g.fontSize ?? 13))"
        }
        return "IBM Plex Mono 12.5"
    }

    /// Variable fonts take the `wght` axis; static families pick the nearest face.
    static func font(family: String, size: Double, weight: Double?) -> NSFont? {
        let size = CGFloat(size)
        guard let regular = NSFontManager.shared.font(withFamily: family, traits: [], weight: 5, size: size) else { return nil }
        guard let weight else { return regular }
        let axes = (CTFontCopyVariationAxes(regular) as? [[CFString: Any]]) ?? []
        if axes.contains(where: { ($0[kCTFontVariationAxisIdentifierKey] as? NSNumber)?.uint32Value == 0x7767_6874 }) {
            let descriptor = regular.fontDescriptor.addingAttributes([
                NSFontDescriptor.AttributeName(rawValue: kCTFontVariationAttribute as String): [NSNumber(value: 0x7767_6874): NSNumber(value: weight)],
            ])
            return NSFont(descriptor: descriptor, size: size) ?? regular
        }
        // CSS 100…900 → NSFontManager 1…12 (400 → 5, 500 → 6, 700 → 9).
        let managerWeight = Int(([100: 2, 200: 3, 300: 4, 400: 5, 500: 6, 600: 8, 700: 9, 800: 10, 900: 11] as [Int: Int])[Int(weight / 100) * 100] ?? 5)
        return NSFontManager.shared.font(withFamily: family, traits: [], weight: managerWeight, size: size) ?? regular
    }
    private(set) var userSchemes: [Base16Scheme] = []
    /// What herdr is set to, for the "Match herdr (…)" label.
    private(set) var herdrActive = "catppuccin"

    var choice: String {
        didSet {
            if !scripted { UserDefaults.standard.set(choice, forKey: Self.choiceKey) }
            resolve()
        }
    }
    /// `--theme ID` at launch: use that theme for this run without saving it.
    private let scripted = PacaApp.argument("--theme") != nil

    var all: [Base16Scheme] { Base16Scheme.builtIn + userSchemes }

    /// Ghostty's keybinds Paca can mirror (text, jump to prompt, scroll), keyed for fast lookup
    /// on every keystroke. Without Ghostty installed, Ghostty's macOS defaults apply.
    var ghosttyKeybinds: [KeyTrigger: GhosttyConfig.KeyAction] {
        if let cached = keybindCache, cached.source == ghostty { return cached.map }
        var map: [KeyTrigger: GhosttyConfig.KeyAction] = [:]
        for (trigger, action) in ghostty?.keyActions ?? GhosttyConfig.defaultKeyActions {
            if let key = KeyTrigger(ghostty: trigger) { map[key] = action }
        }
        keybindCache = (ghostty, map)
        return map
    }
    @ObservationIgnored private var keybindCache: (source: GhosttyConfig?, map: [KeyTrigger: GhosttyConfig.KeyAction])?

    /// Ghostty's theme name for the "Match Ghostty (…)" label.
    var ghosttyThemeName: String? { ghostty?.scheme.map { _ in ghostty?.themeName ?? "custom" } }

    /// Drop Base16 `.yaml` files here to add themes.
    static var userThemesDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".config/paca/themes", isDirectory: true)
    }

    private init() {
        choice = PacaApp.argument("--theme") ?? UserDefaults.standard.string(forKey: Self.choiceKey) ?? Self.matchHerdr
        reloadUserSchemes()
        resolve()
        // Re-check when macOS flips light/dark or Paca comes forward (herdr's config may have changed).
        DistributedNotificationCenter.default().addObserver(forName: .init("AppleInterfaceThemeChangedNotification"), object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { ThemeStore.shared.resolve() }
        }
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { ThemeStore.shared.resolve() }
        }
        NotificationCenter.default.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated {
                ThemeStore.shared.reloadUserSchemes()
                ThemeStore.shared.reloadGhosttyInBackground()
                ThemeStore.shared.resolve()
            }
        }
    }

    static func openUserThemesFolder() {
        try? FileManager.default.createDirectory(at: userThemesDirectory, withIntermediateDirectories: true)
        NSWorkspace.shared.open(userThemesDirectory)
    }

    /// `ghostty +show-config` spawns a process; never block the main thread on it.
    func reloadGhosttyInBackground() {
        Task.detached(priority: .utility) {
            let fresh = GhosttyConfig.load()
            await MainActor.run {
                guard fresh != ThemeStore.shared.ghostty else { return }
                ThemeStore.shared.ghostty = fresh
                ThemeStore.shared.resolve()
            }
        }
    }

    func reloadUserSchemes() {
        let dir = Self.userThemesDirectory
        let files = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
        userSchemes = files
            .filter { ["yaml", "yml"].contains($0.pathExtension.lowercased()) }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
            .compactMap { url in
                guard let text = try? String(contentsOf: url, encoding: .utf8) else { return nil }
                return Base16Scheme.load(yaml: text, id: "user:" + url.deletingPathExtension().lastPathComponent)
            }
    }

    /// macOS's own setting, not Paca's window appearance (which follows the scheme).
    private var systemDark: Bool {
        UserDefaults.standard.string(forKey: "AppleInterfaceStyle") == "Dark"
    }

    func resolve() {
        let dark = systemDark
        herdrActive = HerdrThemeConfig.read().active(systemDark: dark)
        let wanted: String
        switch choice {
        case Self.matchHerdr: wanted = herdrActive
        case Self.matchSystem: wanted = dark ? Base16Scheme.pacaDark.id : Base16Scheme.pacaLight.id
        case Self.matchGhostty: wanted = Self.matchGhostty
        default: wanted = choice
        }
        // herdr's "terminal" theme uses the host terminal's colors; Paca has none, so use its own pair.
        let ghosttyScheme = wanted == Self.matchGhostty ? ghostty?.scheme : nil
        let next = ghosttyScheme ?? all.first { $0.id == wanted } ?? (dark ? .pacaDark : .pacaLight)
        let contrast = NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast
        if next != scheme || contrast != increasedContrast || Theme.palette.scheme != next {
            Theme.palette = ThemePalette(next, increasedContrast: contrast)
            increasedContrast = contrast
            scheme = next
        }
        NSApp?.appearance = NSAppearance(named: next.isDark ? .darkAqua : .aqua)
    }
}
