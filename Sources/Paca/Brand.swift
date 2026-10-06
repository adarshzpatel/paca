import AppKit
import CoreText
import SwiftUI

/// Brand assets from `brand/`, copied in by `scripts/sync-brand.sh`.
enum Brand {
    /// The installed app keeps SwiftPM's resource bundle in Contents/Resources so the app can be
    /// code-signed (macOS only posts notifications for signed apps). `Bundle.module` only looks
    /// next to Contents/, so check Resources first and fall back to it for `swift run`.
    private static let resources: Bundle = Bundle.main.url(forResource: "Paca_Paca", withExtension: "bundle")
        .flatMap(Bundle.init(url:)) ?? Bundle.module

    static func url(_ name: String, _ ext: String) -> URL? {
        resources.url(forResource: name, withExtension: ext)
    }

    private static func image(_ name: String, _ ext: String) -> NSImage {
        url(name, ext).flatMap(NSImage.init(contentsOf:)) ?? NSImage()
    }

    /// Menu bar alpaca. Template, so macOS tints it for light, dark and highlighted bars.
    static let menuBarSymbol: NSImage = {
        let symbol = image("paca-template", "svg")
        symbol.size = NSSize(width: 16, height: 16)
        symbol.isTemplate = true
        return symbol
    }()

    static let wordmarkCream = image("paca-wordmark-cream", "svg")
    static let wordmarkInk = image("paca-wordmark-ink", "svg")
    static let mascot = image("paca-mascot", "png")
    static let appIcon = image("Paca", "icns")

    /// Manrope for display text, IBM Plex Mono for terminals. Process-scoped, nothing installed.
    static func registerFonts() {
        for name in ["Manrope-Variable", "IBMPlexMono-Regular", "IBMPlexMono-Medium"] {
            guard let url = url(name, "ttf") else { continue }
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }
    }

    static func display(_ size: CGFloat, weight: Font.Weight = .semibold) -> Font {
        .custom("Manrope", size: size).weight(weight)
    }

    static func terminalFont(size: CGFloat = 12.5) -> NSFont {
        NSFont(name: "IBMPlexMono", size: size) ?? .monospacedSystemFont(ofSize: size, weight: .regular)
    }
}

/// The `paca` wordmark, cream on dark and ink on light.
struct Wordmark: View {
    @Environment(\.colorScheme) private var scheme
    var height: CGFloat = 20

    var body: some View {
        Image(nsImage: scheme == .dark ? Brand.wordmarkCream : Brand.wordmarkInk)
            .resizable()
            .interpolation(.high)
            .aspectRatio(contentMode: .fit)
            .frame(height: height)
            .accessibilityLabel("Paca")
    }
}

/// Sidebar header: the one-colour alpaca symbol (same glyph as the menu bar) beside the
/// wordmark. Tinted with the theme's secondary text so only status colours carry hue.
struct BrandLockup: View {
    var body: some View {
        HStack(spacing: 7) {
            Image(nsImage: Brand.menuBarSymbol)
                .renderingMode(.template)
                .resizable()
                .interpolation(.high)
                .frame(width: 20, height: 20)
                .foregroundStyle(Theme.text2)
                // Sit on the wordmark's x-height, not the middle of its descender box.
                .offset(y: -2.5)
            Wordmark(height: 19)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Paca")
    }
}

