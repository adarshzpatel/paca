import AppKit
import SwiftUI

/// Phosphor icons (phosphoricons.com), copied in by `scripts/sync-icons.sh`. Paca uses them
/// instead of SF Symbols so its chrome has its own look rather than stock macOS.
enum Icon: String {
    case caretDown = "caret-down"
    case check
    case history = "clock-counter-clockwise"
    case columns
    case folder
    case folderOpen = "folder-open"
    case gear = "gear-six"
    case branch = "git-branch"
    case globe = "globe-simple"
    case house
    case lightning
    case search = "magnifying-glass"
    case palette
    case plugs
    case plus
    case plusCircle = "plus-circle"
    case rows
    case sidebar = "sidebar-simple"
    case sparkle
    case terminal = "terminal-window"
    case trash
    case tray
    case warning
    case warningCircle = "warning-circle"
    case x

    /// Bold matches the weight of Paca's medium text; regular reads faint at 11–15 pt.
    enum Weight: String { case bold, fill }

    /// Template image at `side` points, so `foregroundStyle` tints it. Sized here rather than
    /// with `.resizable()` because `Menu` labels ignore SwiftUI frames. SVGs stay sharp at any size.
    @MainActor func image(_ weight: Weight, side: CGFloat) -> NSImage {
        let key = "ph-\(rawValue)-\(weight.rawValue)"
        let sizedKey = "\(key)@\(side)"
        if let cached = Self.cache[sizedKey] { return cached }
        let source = Brand.url(key, "svg").flatMap(NSImage.init(contentsOf:)) ?? NSImage()
        let image = source.copy() as! NSImage
        image.size = NSSize(width: side, height: side)
        image.isTemplate = true
        Self.cache[sizedKey] = image
        return image
    }

    @MainActor private static var cache: [String: NSImage] = [:]
}

/// An icon that stands in for an SF Symbol at the same font size. Phosphor's glyphs sit inside
/// padding on a 256 grid, so the frame is a little larger than `size` to match optically.
struct PhIcon: View {
    let icon: Icon
    var size: CGFloat = 13
    var weight: Icon.Weight = .bold

    init(_ icon: Icon, size: CGFloat = 13, weight: Icon.Weight = .bold) {
        self.icon = icon
        self.size = size
        self.weight = weight
    }

    var body: some View {
        let side = (size * 1.2).rounded()
        Image(nsImage: icon.image(weight, side: side))
            .renderingMode(.template)
            .accessibilityHidden(true)
    }
}

/// Agent logos from LobeHub Icons, copied in by `scripts/sync-agent-icons.sh` and named by
/// herdr's agent kind (`agent-claude.svg`). Nil for kinds without a logo.
enum AgentLogo {
    @MainActor static func image(for kind: String, side: CGFloat) -> NSImage? {
        let key = "\(kind)@\(side)"
        if let cached = cache[key] { return cached }
        guard let source = Brand.url("agent-\(kind)", "svg").flatMap(NSImage.init(contentsOf:)) else {
            cache[key] = .some(nil)
            return nil
        }
        let image = source.copy() as! NSImage
        image.size = NSSize(width: side, height: side)
        image.isTemplate = true
        cache[key] = image
        return image
    }

    @MainActor private static var cache: [String: NSImage?] = [:]
}
