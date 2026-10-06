import HerdrKit
import SwiftUI

struct DetailView: View {
    @Environment(HerdrStore.self) private var store
    @AppStorage("paca.splitRatio") private var ratio = 0.5

    /// Every open tab stays attached; panes not in a slot are hidden. Releasing a pane hands its
    /// size back to herdr's layout and each size change makes agents redraw, so neither switching
    /// tabs nor moving a pane between split slots detaches it.
    var body: some View {
        let slots = store.slots
        let split = store.splitAxis
        GeometryReader { geo in
            let rects = Self.rects(for: slots.count, axis: split, ratio: ratio, in: geo.size)
            let focusedRect = rects[min(store.focusedSlot, rects.count - 1)]
            ZStack(alignment: .topLeading) {
                if slots.allSatisfy({ $0 == nil }) && split == nil { EmptyDetail() }

                ForEach(store.tabs) { pane in
                    let slot = slots.firstIndex(of: pane.paneId)
                    let rect = slot.map { rects[$0] } ?? focusedRect
                    PaneDetail(
                        pane: pane,
                        isVisible: slot != nil,
                        isFocused: pane.paneId == store.selectedPaneId,
                        showsHeader: split != nil
                    )
                    .frame(width: rect.width, height: rect.height)
                    .offset(x: rect.minX, y: rect.minY)
                    .opacity(slot != nil ? 1 : 0)
                    .allowsHitTesting(slot != nil)
                    .accessibilityHidden(slot == nil)
                }

                if split != nil {
                    ForEach(Array(slots.enumerated()), id: \.offset) { index, id in
                        if id == nil {
                            SplitPicker()
                                .frame(width: rects[index].width, height: rects[index].height)
                                .offset(x: rects[index].minX, y: rects[index].minY)
                        }
                    }
                    SplitDivider(axis: split!, ratio: $ratio, size: geo.size)
                }
            }
        }
        .background(Theme.terminal)
    }

    /// Slot frames: whole area, or two parts split at `ratio` with a 1pt divider between.
    static func rects(for count: Int, axis: HerdrStore.SplitAxis?, ratio: Double, in size: CGSize) -> [CGRect] {
        guard count == 2, let axis else { return [CGRect(origin: .zero, size: size)] }
        switch axis {
        case .horizontal:
            let first = (size.width * ratio).rounded()
            return [CGRect(x: 0, y: 0, width: first, height: size.height),
                    CGRect(x: first + 1, y: 0, width: size.width - first - 1, height: size.height)]
        case .vertical:
            let first = (size.height * ratio).rounded()
            return [CGRect(x: 0, y: 0, width: size.width, height: first),
                    CGRect(x: 0, y: first + 1, width: size.width, height: size.height - first - 1)]
        }
    }
}

/// The line between split slots. Drag to resize; terminals resize once you pause.
private struct SplitDivider: View {
    let axis: HerdrStore.SplitAxis
    @Binding var ratio: Double
    let size: CGSize
    @State private var start: Double?
    @State private var hovering = false

    var body: some View {
        let horizontal = axis == .horizontal
        let position = (horizontal ? size.width : size.height) * ratio
        Theme.hairline
            .frame(width: horizontal ? 1 : size.width, height: horizontal ? size.height : 1)
            .overlay {
                ResizeHighlight(active: hovering || start != nil, vertical: horizontal)
                Color.clear
                    .frame(width: horizontal ? 9 : size.width, height: horizontal ? size.height : 9)
                    .contentShape(Rectangle())
                    .onHover { inside in
                        guard inside != hovering else { return }
                        hovering = inside
                        if inside { (horizontal ? NSCursor.resizeLeftRight : NSCursor.resizeUpDown).push() } else { NSCursor.pop() }
                    }
                    .gesture(
                        DragGesture(minimumDistance: 1)
                            .onChanged { value in
                                let begin = start ?? ratio
                                start = begin
                                let total = horizontal ? size.width : size.height
                                let delta = (horizontal ? value.translation.width : value.translation.height) / max(total, 1)
                                ratio = min(max(begin + delta, 0.2), 0.8)
                            }
                            .onEnded { _ in start = nil }
                    )
            }
            .offset(x: horizontal ? position.rounded() : 0, y: horizontal ? 0 : position.rounded())
            // Closing the split under the pointer would otherwise leave the resize cursor pushed.
            .onDisappear {
                if hovering { NSCursor.pop() }
                hovering = false
            }
            .accessibilityElement()
            .accessibilityLabel("Split divider")
            .accessibilityValue("\(Int(ratio * 100)) percent")
            .accessibilityAdjustableAction { direction in
                ratio = min(max(ratio + (direction == .increment ? 0.05 : -0.05), 0.2), 0.8)
            }
    }
}

/// An empty split slot: pick which open tab or pane to show here.
private struct SplitPicker: View {
    @Environment(HerdrStore.self) private var store

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Open in this split")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Theme.text2)
                .padding(.bottom, 4)
            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(store.panes.filter { !store.slots.contains($0.paneId) }) { pane in
                        Button { store.showInSplit(pane.paneId) } label: {
                            HStack(spacing: 8) {
                                if pane.isAgent { StatusGlyph(status: pane.agentStatus) } else {
                                    PhIcon(.terminal, size: 11).foregroundStyle(Theme.text3)
                                }
                                Text(pane.displayName).font(.system(size: 13)).foregroundStyle(Theme.text).lineLimit(1)
                                if let ws = store.workspace(id: pane.workspaceId) { WorkspacePill(workspace: ws) }
                                Spacer(minLength: 0)
                            }
                            .padding(.horizontal, 10)
                            .frame(height: 32)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(RowButtonStyle())
                    }
                }
            }
            .frame(maxWidth: 420)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Theme.content)
    }
}

private struct PaneDetail: View {
    @Environment(HerdrStore.self) private var store
    let pane: Pane
    var isVisible = true
    var isFocused = true
    var showsHeader = false
    @State private var detachReason: String?
    @State private var detached = false
    @State private var takeoverToken = 0

    var body: some View {
        VStack(spacing: 0) {
            if showsHeader { header }
            ZStack {
                LiveTerminal(
                    paneId: pane.paneId,
                    socketPath: store.socketPath,
                    takeoverToken: takeoverToken,
                    isActive: isVisible,
                    isFocused: isFocused,
                    onFocus: { [store, id = pane.paneId] in
                        if store.selectedPaneId != id { store.selectedPaneId = id }
                    },
                    onPaneCommand: { [store, id = pane.paneId] command in
                        Task { await store.perform(command, on: id) }
                    },
                    onDetached: { reason in
                        detachReason = reason
                        detached = true
                    }
                )
                .padding(.leading, 16)
                .padding(.trailing, 8)
                .padding(.top, 10)

                if detached {
                    DetachedCard(reason: detachReason) {
                        detached = false
                        takeoverToken += 1
                    }
                }
            }
            .background(Theme.terminal)
        }
        // In a split, the focused side gets an accent outline.
        .overlay {
            if showsHeader && isFocused {
                Rectangle().strokeBorder(Theme.accent.opacity(0.55), lineWidth: 1)
            }
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            if pane.isAgent { StatusGlyph(status: pane.agentStatus, size: 11) }
            Text(pane.displayName)
                .font(.system(size: 12, weight: isFocused ? .medium : .regular))
                .foregroundStyle(isFocused ? Theme.text : Theme.text3)
                .lineLimit(1)
            if let ws = store.workspace(id: pane.workspaceId) { WorkspacePill(workspace: ws) }
            Spacer(minLength: 4)
            IconButton(icon: .x, help: "Remove from split (tab stays open)", tipEdge: .leading) {
                store.removeFromSplit(pane.paneId)
            }
        }
        .padding(.leading, 12)
        .padding(.trailing, 4)
        .frame(height: 30)
        .background(Theme.chrome)
        .overlay(alignment: .bottom) { Theme.hairline.frame(height: 1) }
        .contentShape(Rectangle())
        .onTapGesture { store.selectedPaneId = pane.paneId }
        .pointerCursor()
    }
}

private struct DetachedCard: View {
    let reason: String?
    let takeOver: () -> Void

    var body: some View {
        VStack(spacing: 10) {
            PhIcon(.plugs, size: 20)
                .foregroundStyle(Theme.text3)
            Text("Another client is controlling this pane")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Theme.text)
            if let reason {
                Text(reason)
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.text3)
                    .multilineTextAlignment(.center)
            }
            Button("Take over", action: takeOver)
                .keyboardShortcut(.defaultAction)
                .controlSize(.large)
                .padding(.top, 4)
        }
        .padding(24)
        .frame(maxWidth: 380)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.hairline))
        .shadow(color: .black.opacity(0.3), radius: 24, y: 10)
    }
}

private struct EmptyDetail: View {
    @Environment(HerdrStore.self) private var store

    var body: some View {
        VStack(spacing: 14) {
            Image(nsImage: Brand.mascot)
                .resizable()
                .interpolation(.high)
                .frame(width: 132, height: 132)
                .accessibilityHidden(true)
            if store.connectionError != nil {
                Text("herdr isn't running")
                    .font(Brand.display(28))
                    .foregroundStyle(Theme.text)
                Text("Start it with `herdr` in a terminal. Paca reconnects on its own.")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.text3)
            } else {
                Text("What should we check on?")
                    .font(Brand.display(28))
                    .foregroundStyle(Theme.text)
                Text(summary)
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.text3)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.content)
    }

    private var summary: String {
        let agents = store.panes.filter(\.isAgent)
        let parts = [
            (store.needsYou.count, "need you"),
            (store.count(.working), "working"),
            (agents.filter { $0.agentStatus == .idle }.count, "idle"),
        ]
        .filter { $0.0 > 0 }
        .map { "\($0.0) \($0.1)" }
        return parts.isEmpty ? "No agents running. Start one with New agent." : parts.joined(separator: " · ")
    }
}
