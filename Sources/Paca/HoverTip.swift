import Observation
import SwiftUI

/// Instant hover labels for icon-only controls, like Slack's rail. System tooltips (`.help`)
/// wait about a second and vanish on the slightest move, which left the rail and toolbar
/// unexplained. Labels draw in one layer at the window root, so sidebars and scroll views
/// can't clip them.
@MainActor
@Observable
final class HoverTipCenter {
    static let shared = HoverTipCenter()
    static let space = "paca.root"

    struct Tip: Equatable {
        let id: UUID
        let text: String
        let shortcut: String?
        let anchor: CGRect
        let edge: Edge
    }

    private(set) var tip: Tip?
    @ObservationIgnored private var pending: DispatchWorkItem?
    /// Debug only: last known tip per text, so `--tip TEXT` can show one for a snapshot.
    @ObservationIgnored var registry: [String: Tip] = [:]

    func showRegistered(_ text: String) {
        if let match = registry.first(where: { $0.key.hasPrefix(text) })?.value { tip = match }
    }

    func show(_ tip: Tip) {
        pending?.cancel()
        // Moving straight from one control to the next swaps the label at once.
        let delay = self.tip == nil ? 0.35 : 0.0
        let work = DispatchWorkItem { [weak self] in self?.tip = tip }
        pending = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    func hide(_ id: UUID) {
        pending?.cancel()
        if tip?.id == id { tip = nil }
    }
}

private struct HoverTipModifier: ViewModifier {
    let text: String
    let shortcut: String?
    let edge: Edge
    @State private var id = UUID()
    @State private var frame: CGRect = .zero

    func body(content: Content) -> some View {
        content
            .background {
                GeometryReader { geo in
                    let rect = geo.frame(in: .named(HoverTipCenter.space))
                    Color.clear
                        .onAppear { frame = rect; register(rect) }
                        .onChange(of: rect) { _, new in frame = new; register(new) }
                }
            }
            .onHover { inside in
                if inside {
                    HoverTipCenter.shared.show(.init(id: id, text: text, shortcut: shortcut, anchor: frame, edge: edge))
                } else {
                    HoverTipCenter.shared.hide(id)
                }
            }
            .onDisappear { HoverTipCenter.shared.hide(id) }
            // VoiceOver reads the same text as a hint.
            .accessibilityHint(shortcut.map { "\(text), \($0)" } ?? text)
    }
}

extension HoverTipModifier {
    fileprivate func register(_ rect: CGRect) {
        guard debugEnabled else { return }
        HoverTipCenter.shared.registry[text] = .init(id: id, text: text, shortcut: shortcut, anchor: rect, edge: edge)
    }
}

extension View {
    /// Shows `text` (and `shortcut`) beside the view on hover. Use for icon-only controls.
    func hoverTip(_ text: String, shortcut: String? = nil, edge: Edge = .bottom) -> some View {
        modifier(HoverTipModifier(text: text, shortcut: shortcut, edge: edge))
    }
}

/// The single label, placed in RootView's overlay.
struct HoverTipLayer: View {
    @State private var size: CGSize = .zero

    var body: some View {
        GeometryReader { geo in
            if let tip = HoverTipCenter.shared.tip {
                label(tip)
                    .fixedSize()
                    .background {
                        GeometryReader { inner in
                            Color.clear
                                .onAppear { size = inner.size }
                                .onChange(of: inner.size) { _, new in size = new }
                        }
                    }
                    .offset(position(for: tip, in: geo.size))
                    .transition(.opacity)
                    .id(tip.id)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .animation(.easeOut(duration: 0.08), value: HoverTipCenter.shared.tip)
    }

    private func label(_ tip: Tip) -> some View {
        HStack(spacing: 8) {
            Text(tip.text)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Theme.text)
                .multilineTextAlignment(.leading)
            if let shortcut = tip.shortcut {
                Kbd(shortcut)
            }
        }
        .padding(.leading, 9)
        .padding(.trailing, tip.shortcut == nil ? 9 : 5)
        .padding(.vertical, 5)
        .background(RoundedRectangle(cornerRadius: 7).fill(Theme.card))
        .overlay(RoundedRectangle(cornerRadius: 7).stroke(Theme.hairline))
        .shadow(color: .black.opacity(0.25), radius: 8, y: 3)
    }

    private typealias Tip = HoverTipCenter.Tip

    /// Beside the control for the rail (trailing), below it for toolbars; kept inside the window.
    private func position(for tip: Tip, in bounds: CGSize) -> CGSize {
        let a = tip.anchor
        var x: CGFloat, y: CGFloat
        switch tip.edge {
        case .trailing:
            x = a.maxX + 8
            y = a.midY - size.height / 2
        case .leading:
            x = a.minX - size.width - 8
            y = a.midY - size.height / 2
        case .top:
            x = a.midX - size.width / 2
            y = a.minY - size.height - 6
        case .bottom:
            x = a.midX - size.width / 2
            y = a.maxY + 6
        }
        x = min(max(x, 8), bounds.width - size.width - 8)
        y = min(max(y, 8), bounds.height - size.height - 8)
        return CGSize(width: x, height: y)
    }
}
