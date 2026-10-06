import AppKit
import SwiftUI

/// The Dock icon picked in Settings. Applied with `NSApp.applicationIconImage`, so it shows
/// while Paca runs; Finder and Launchpad keep the bundle's icon, because writing a custom
/// icon into the bundle would break its code signature (and with it, notifications).
enum AppIcon: String, CaseIterable, Identifiable {
    case standard, charcoal, lavender, mint

    static let key = "paca.appIcon"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .standard: "Paca"
        case .charcoal: "Charcoal"
        case .lavender: "Lavender"
        case .mint: "Mint"
        }
    }

    var image: NSImage {
        switch self {
        case .standard: Brand.appIcon
        default: Brand.url("paca-app-icon-\(rawValue)", "png").flatMap(NSImage.init(contentsOf:)) ?? Brand.appIcon
        }
    }

    static var current: AppIcon {
        UserDefaults.standard.string(forKey: key).flatMap(AppIcon.init(rawValue:)) ?? .standard
    }

    @MainActor static func apply(_ icon: AppIcon = current) {
        // The installed app's layered icon renders best as itself: nil hands the Dock back to it.
        // A bare SwiftPM launch has no bundle icon, so it always needs an image.
        let bundled = Bundle.main.object(forInfoDictionaryKey: "CFBundleIconName") != nil
            || Bundle.main.object(forInfoDictionaryKey: "CFBundleIconFile") != nil
        NSApp.applicationIconImage = icon == .standard && bundled ? nil : icon.image
    }
}

/// A row of icon thumbnails; the picked one gets the accent ring.
struct AppIconPicker: View {
    @AppStorage(AppIcon.key) private var choice = AppIcon.standard.rawValue

    var body: some View {
        LabeledContent("App icon") {
            HStack(spacing: Theme.space) {
                ForEach(AppIcon.allCases) { icon in
                    let picked = icon.rawValue == choice
                    Button {
                        choice = icon.rawValue
                        AppIcon.apply(icon)
                    } label: {
                        Image(nsImage: icon.image)
                            .resizable()
                            .frame(width: 44, height: 44)
                            .padding(2)
                            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(picked ? Theme.accent : .clear, lineWidth: 2))
                    }
                    .buttonStyle(.plain)
                    .pointerCursor()
                    .help(icon.title)
                    .accessibilityLabel(icon.title)
                    .accessibilityAddTraits(picked ? [.isButton, .isSelected] : .isButton)
                }
            }
        }
    }
}
