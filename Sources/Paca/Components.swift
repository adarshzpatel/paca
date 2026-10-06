import AppKit
import HerdrKit
import SwiftUI

struct Spinner: View {
    var color: Color?
    var lineWidth: CGFloat = 1.6
    @State private var spinning = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.systemColors) private var system

    var body: some View {
        let color = color ?? (system ? Color(nsColor: .systemBlue) : Theme.working)
        // With Reduce motion on, the open ring still reads as "working" without spinning.
        Circle()
            .trim(from: 0.15, to: 1)
            .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
            .rotationEffect(.degrees(spinning && !reduceMotion ? 360 : 0))
            .animation(reduceMotion ? nil : .linear(duration: 0.9).repeatForever(autoreverses: false), value: spinning)
            .onAppear { spinning = true }
    }
}

/// Status mark used in rows and headers. Idle agents get a quiet dot; shells get nothing.
struct StatusGlyph: View {
    let status: AgentStatus
    var isAgent = true
    var size: CGFloat = 12
    @Environment(\.systemColors) private var system

    var body: some View {
        Group {
            switch status {
            case .working:
                Spinner().padding(1)
            case .blocked:
                PhIcon(.warningCircle, size: size - 1, weight: .fill)
                    .foregroundStyle(system ? Color(nsColor: .systemOrange) : Theme.blocked)
            case .done:
                PhIcon(.check, size: size - 2)
                    .foregroundStyle(system ? Color(nsColor: .systemGreen) : Theme.done)
            case .idle, .unknown:
                if isAgent {
                    Circle().fill(system ? Color(nsColor: .tertiaryLabelColor) : Theme.text4).frame(width: 6, height: 6)
                }
            }
        }
        .frame(width: size, height: size)
        .accessibilityLabel(status.title ?? "Idle")
    }
}

struct StatusPill: View {
    let status: AgentStatus

    var body: some View {
        if let title = status.title {
            let tint = Theme.color(for: status)
            Text(title)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(tint)
                .padding(.horizontal, 8)
                .frame(height: 20)
                .background(tint.opacity(0.14), in: Capsule())
        }
    }
}

struct CountBadge: View {
    let count: Int
    var tint: Color = Theme.accent

    var body: some View {
        Text("\(count)")
            .font(.system(size: 11, weight: .bold).monospacedDigit())
            .foregroundStyle(Theme.onAccent)
            .padding(.horizontal, 5)
            .frame(minWidth: 18, minHeight: 18)
            .background(tint, in: RoundedRectangle(cornerRadius: 5))
    }
}

struct IconButton: View {
    let icon: Icon
    let help: String
    var shortcut: String?
    var tipEdge: Edge = .bottom
    let action: () -> Void
    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            PhIcon(icon, size: 13)
                .foregroundStyle(hovered ? Theme.text2 : Theme.text3)
                .frame(width: 26, height: 24)
                .background(RoundedRectangle(cornerRadius: 6).fill(hovered ? Theme.wash : .clear))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
        .pointerCursor()
        .hoverTip(help, shortcut: shortcut, edge: tipEdge)
        .accessibilityLabel(help)
    }
}

/// Rounded wash on hover and selection, like the Codex sidebar.
struct RowButtonStyle: ButtonStyle {
    var selected = false
    /// Keeps the content lit when the pointer is on a control laid over the row.
    var lit = false

    func makeBody(configuration: Configuration) -> some View {
        RowBody(configuration: configuration, selected: selected, lit: lit)
    }

    private struct RowBody: View {
        let configuration: Configuration
        let selected: Bool
        let lit: Bool
        @State private var hovered = false
        @Environment(\.systemColors) private var system

        var body: some View {
            configuration.label
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(selected || configuration.isPressed ? (system ? Color.primary.opacity(0.12) : Theme.washStrong)
                              : hovered ? (system ? Color.primary.opacity(0.07) : Theme.wash) : .clear)
                )
                .onHover { hovered = $0 }
                .pointerCursor()
                .environment(\.rowLit, selected || lit || hovered || configuration.isPressed)
        }
    }
}

private struct RowLitKey: EnvironmentKey { static let defaultValue = false }
private struct SystemColorsKey: EnvironmentKey { static let defaultValue = false }

extension EnvironmentValues {
    /// True where views sit on system materials (the menu bar panel): draw with macOS label
    /// and system colors, which follow light/dark and Increase contrast, not the Paca palette.
    var systemColors: Bool {
        get { self[SystemColorsKey.self] }
        set { self[SystemColorsKey.self] = newValue }
    }

    /// True inside a `RowButtonStyle` row that is hovered, pressed or selected.
    /// A plain key rather than `@Entry`, which needs Xcode's macro plugins.
    var rowLit: Bool {
        get { self[RowLitKey.self] }
        set { self[RowLitKey.self] = newValue }
    }
}

/// Row content sits a step dim and brightens while its row is lit, so the sidebar reads
/// calm and the row under the pointer stands out.
private struct RowLit: ViewModifier {
    @Environment(\.rowLit) private var lit
    let dim: Color
    let bright: Color
    let dimOpacity: Double

    func body(content: Content) -> some View {
        content
            .foregroundStyle(lit ? bright : dim)
            .opacity(lit ? 1 : dimOpacity)
            .animation(.easeOut(duration: 0.12), value: lit)
    }
}

extension View {
    /// Text and icons: `dim` normally, `bright` when the row is lit.
    func rowForeground(_ dim: Color = Theme.text2, lit bright: Color = Theme.text) -> some View {
        modifier(RowLit(dim: dim, bright: bright, dimOpacity: 1))
    }

    /// Colored marks (folder tints) keep their color and just fade back a little.
    func rowTinted(_ color: Color, dimOpacity: Double = 0.75) -> some View {
        modifier(RowLit(dim: color, bright: color, dimOpacity: dimOpacity))
    }
}

/// Pointing-hand cursor while hovering. `.pointerStyle(.link)` needs macOS 15, so this
/// pushes and pops `NSCursor` itself, and pops on disappear so the stack never leaks.
struct PointerCursor: ViewModifier {
    @Environment(\.isEnabled) private var isEnabled
    @State private var pushed = false

    func body(content: Content) -> some View {
        content
            .onHover { inside in set(inside && isEnabled) }
            .onChange(of: isEnabled) { _, enabled in if !enabled { set(false) } }
            .onDisappear { set(false) }
    }

    private func set(_ on: Bool) {
        guard on != pushed else { return }
        pushed = on
        if on { NSCursor.pointingHand.push() } else { NSCursor.pop() }
    }
}

extension View {
    func pointerCursor() -> some View { modifier(PointerCursor()) }
}

extension Pane {
    var isAgent: Bool { agent != nil }
    var kind: String? { displayAgent ?? agent }
}

/// Workspace name in a small capsule with its color dot, for tabs and split headers.
struct WorkspacePill: View {
    @Environment(HerdrStore.self) private var store
    let workspace: Workspace
    /// Bold name in the workspace's color, no dot or capsule. Tabs use it so each tab isn't a
    /// box inside a box, and the status glyph isn't followed by a second dot.
    var bare = false

    var body: some View {
        HStack(spacing: 5) {
            if !bare {
                Circle()
                    .fill(Theme.workspaceTint(workspace.workspaceId, scope: store.workspaceScope))
                    .frame(width: 6, height: 6)
            }
            Text(store.title(of: workspace))
                .font(.system(size: bare ? 12 : 11, weight: bare ? .bold : .medium))
                .foregroundStyle(bare ? Theme.workspaceTint(workspace.workspaceId, scope: store.workspaceScope, text: true) : Theme.text2)
                .lineLimit(1)
        }
        .padding(.horizontal, bare ? 0 : 6)
        .frame(height: 18)
        .background(Capsule().fill(bare ? .clear : Theme.wash))
        .overlay(Capsule().stroke(bare ? .clear : Theme.hairline))
        .fixedSize()
        .accessibilityLabel("Workspace \(store.title(of: workspace))")
    }
}


/// Accent line over a resize handle while it's hovered or dragged. Fades in after a short
/// delay so passing the pointer across a divider doesn't flash it.
struct ResizeHighlight: View {
    let active: Bool
    /// True for a vertical line (a handle you drag sideways).
    let vertical: Bool

    var body: some View {
        Theme.accent
            .frame(width: vertical ? 3 : nil, height: vertical ? nil : 3)
            .opacity(active ? 1 : 0)
            .animation(active ? .easeOut(duration: 0.12).delay(0.08) : .easeOut(duration: 0.2), value: active)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

// MARK: Scroll edge fade

/// Shared between `scrollFade` (on the ScrollView) and `scrollFadeContent` (on its content).
@MainActor @Observable
private final class ScrollFadeMetrics {
    var content: CGRect = .zero
    var viewport: CGFloat = 0
}

private struct ScrollFadeMetricsKey: EnvironmentKey {
    static let defaultValue: ScrollFadeMetrics? = nil
}

extension EnvironmentValues {
    fileprivate var scrollFadeMetrics: ScrollFadeMetrics? {
        get { self[ScrollFadeMetricsKey.self] }
        set { self[ScrollFadeMetricsKey.self] = newValue }
    }
}

private let scrollFadeSpace = "scrollFade"

/// Fades a scroll view's edges, each only while content is hidden past it. Put
/// `scrollFadeContent()` on the content and `scrollFade(_:)` on the `ScrollView`.
private struct ScrollFade: ViewModifier {
    let axis: Axis
    let length: CGFloat
    let onViewportChange: ((CGFloat) -> Void)?
    @State private var metrics = ScrollFadeMetrics()

    private var hiddenStart: Bool { (axis == .horizontal ? metrics.content.minX : metrics.content.minY) < -1 }
    private var hiddenEnd: Bool {
        metrics.viewport > 0 && (axis == .horizontal ? metrics.content.maxX : metrics.content.maxY) > metrics.viewport + 1
    }

    func body(content view: Content) -> some View {
        view
            .environment(\.scrollFadeMetrics, metrics)
            .coordinateSpace(name: scrollFadeSpace)
            .background {
                GeometryReader { box in
                    let size = axis == .horizontal ? box.size.width : box.size.height
                    Color.clear
                        .onAppear { metrics.viewport = size; onViewportChange?(size) }
                        .onChange(of: size) { _, size in metrics.viewport = size; onViewportChange?(size) }
                }
            }
            .mask(mask)
    }

    private var mask: some View {
        let layout = axis == .horizontal ? AnyLayout(HStackLayout(spacing: 0)) : AnyLayout(VStackLayout(spacing: 0))
        let (start, end): (UnitPoint, UnitPoint) = axis == .horizontal ? (.leading, .trailing) : (.top, .bottom)
        return layout {
            edge(colors: [.clear, .black], from: start, to: end, hidden: hiddenStart)
            Color.black
            edge(colors: [.black, .clear], from: start, to: end, hidden: hiddenEnd)
        }
        .animation(.easeOut(duration: 0.15), value: hiddenStart)
        .animation(.easeOut(duration: 0.15), value: hiddenEnd)
    }

    private func edge(colors: [Color], from: UnitPoint, to: UnitPoint, hidden: Bool) -> some View {
        LinearGradient(colors: colors, startPoint: from, endPoint: to)
            .frame(width: axis == .horizontal ? length : nil, height: axis == .vertical ? length : nil)
            .opacity(hidden ? 1 : 0)
            .background(Color.black.opacity(hidden ? 0 : 1))
    }
}

/// Reports the content's frame in the scroll view's space as it scrolls or resizes.
private struct ScrollFadeContent: ViewModifier {
    @Environment(\.scrollFadeMetrics) private var metrics

    func body(content: Content) -> some View {
        content.background {
            GeometryReader { box in
                let frame = box.frame(in: .named(scrollFadeSpace))
                Color.clear
                    .onAppear { metrics?.content = frame }
                    .onChange(of: frame) { _, frame in metrics?.content = frame }
            }
        }
    }
}

extension View {
    /// On a `ScrollView`: fade the edges where content is hidden. `onViewportChange` reports
    /// the visible length along `axis`.
    func scrollFade(_ axis: Axis, length: CGFloat = 24, onViewportChange: ((CGFloat) -> Void)? = nil) -> some View {
        modifier(ScrollFade(axis: axis, length: length, onViewportChange: onViewportChange))
    }

    /// On the scroll view's content, so `scrollFade` can see how far it overflows.
    func scrollFadeContent() -> some View { modifier(ScrollFadeContent()) }
}

/// A fast in-window dialog: dims the window and pops the card in over ~120 ms. macOS sheets
/// slide down from the title bar and take noticeably longer, which made frequent actions
/// like New agent feel sluggish. Esc, a click outside, or `close` dismisses.
struct QuickModal<Card: View>: View {
    let close: () -> Void
    @ViewBuilder let card: () -> Card

    var body: some View {
        ZStack {
            Color.black.opacity(0.28)
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture(perform: close)
                .accessibilityHidden(true)
            card()
                .background(RoundedRectangle(cornerRadius: 14).fill(Theme.card))
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.hairline))
                .shadow(color: .black.opacity(0.35), radius: 30, y: 12)
                .onExitCommand(perform: close)
                .transition(.asymmetric(insertion: .scale(scale: 0.97).combined(with: .opacity),
                                        removal: .opacity))
                .accessibilityAddTraits(.isModal)
        }
    }
}

/// The fade and pop used by QuickModal. Short enough to feel instant, long enough to read as motion.
extension Animation {
    static let quickModal = Animation.easeOut(duration: 0.12)
}

/// A keyboard shortcut drawn as keycaps, one per key: "⌘⇧D" → [⌘] [⇧] [D].
struct Kbd: View {
    let shortcut: String

    @Environment(\.systemColors) private var system

    init(_ shortcut: String) { self.shortcut = shortcut }

    var body: some View {
        HStack(spacing: 3) {
            ForEach(Array(Self.keys(shortcut).enumerated()), id: \.offset) { _, key in
                Text(key)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(system ? Color(nsColor: .secondaryLabelColor) : Theme.text2)
                    .frame(minWidth: 18, minHeight: 18)
                    .padding(.horizontal, key.count > 1 ? 4 : 0)
                    .background(RoundedRectangle(cornerRadius: 4).fill(system ? Color.primary.opacity(0.06) : Theme.wash))
                    .overlay(RoundedRectangle(cornerRadius: 4).stroke(system ? Color(nsColor: .separatorColor) : Theme.hairline))
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(shortcut)
    }

    /// Modifier glyphs are keys of their own; whatever follows them is the final key.
    static func keys(_ shortcut: String) -> [String] {
        let modifiers: Set<Character> = ["⌃", "⌥", "⇧", "⌘"]
        var keys: [String] = []
        var rest = Substring(shortcut)
        while let first = rest.first, modifiers.contains(first) {
            keys.append(String(first))
            rest = rest.dropFirst()
        }
        if !rest.isEmpty { keys.append(String(rest)) }
        return keys
    }
}
