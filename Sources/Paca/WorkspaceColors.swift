import AppKit
import Observation

/// Folder colors picked from a workspace's context menu. Saved in UserDefaults per machine,
/// session and workspace, since herdr's workspace ids (`w1`, `w2`…) repeat across sessions.
/// Workspaces without a pick keep their automatic hashed tint.
@MainActor @Observable
final class WorkspaceColors {
    static let shared = WorkspaceColors()
    private static let key = "paca.workspaceColors"

    /// Base16 accent slots offered in the menu, in hue order.
    static let choices: [(name: String, slot: Int)] = [
        ("Red", 0x08), ("Orange", 0x09), ("Yellow", 0x0A), ("Green", 0x0B),
        ("Cyan", 0x0C), ("Blue", 0x0D), ("Purple", 0x0E), ("Brown", 0x0F),
    ]

    private var slots: [String: Int] = UserDefaults.standard.dictionary(forKey: WorkspaceColors.key) as? [String: Int] ?? [:] {
        didSet { UserDefaults.standard.set(slots, forKey: Self.key) }
    }

    func slot(for id: String, scope: String) -> Int? { slots["\(scope)/\(id)"] }

    func set(_ slot: Int?, for id: String, scope: String) { slots["\(scope)/\(id)"] = slot }

    /// A filled dot for menu items. Not a template, so the menu keeps its color.
    static func swatch(_ color: NSColor) -> NSImage {
        NSImage(size: NSSize(width: 12, height: 12), flipped: false) { rect in
            color.setFill()
            NSBezierPath(ovalIn: rect.insetBy(dx: 1, dy: 1)).fill()
            return true
        }
    }
}
