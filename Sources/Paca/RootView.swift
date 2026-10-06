import AppKit
import HerdrKit
import SwiftUI

struct RootView: View {
    @Environment(HerdrStore.self) private var store
    @State private var titlebarHeight: CGFloat = 38
    @State private var sidebarVisible = true

    @AppStorage("paca.sidebarWidth") private var sidebarWidth: Double = 288
    @State private var paletteOpen = PacaApp.argument("--palette") != nil

    static let railWidth: CGFloat = 38 + 2 * Theme.space

    var body: some View {
        @Bindable var store = store
        return VStack(spacing: 0) {
            TopBar(sidebarVisible: $sidebarVisible, contentLeading: detailLeading)
            HStack(spacing: 0) {
                Rail()
                panel
            }
        }
        .background(Theme.chrome)
        .background(WindowChrome(titlebarHeight: $titlebarHeight))
        .coordinateSpace(name: HoverTipCenter.space)
        .overlay(alignment: .topLeading) { HoverTipLayer() }
        .ignoresSafeArea()
        .background(
            Button("") { withAnimation(.easeInOut(duration: 0.2)) { sidebarVisible.toggle() } }
                .keyboardShortcut("b", modifiers: .command)
                .hidden()
        )
        .background(
            Button("") { paletteOpen.toggle() }
                .keyboardShortcut("k", modifiers: .command)
                .hidden()
        )
        .onAppear { AppShortcuts.install(store: store) }
        .overlay {
            if let request = store.newAgentRequest {
                QuickModal(close: { store.newAgentRequest = nil }) {
                    NewAgentSheet(initialWorkspace: request.workspace) { store.newAgentRequest = nil }
                        .environment(store)
                }
            }
        }
        .animation(.quickModal, value: store.newAgentRequest?.id)
        .overlay {
            if paletteOpen {
                CommandPalette(initialQuery: PacaApp.argument("--palette") ?? "") { paletteOpen = false }
            }
        }
    }

    /// Inset panel with a rounded top-left corner, like Codex.
    private var panel: some View {
        let shape = UnevenRoundedRectangle(topLeadingRadius: 12)
        return HStack(spacing: 0) {
            if sidebarVisible {
                Sidebar()
                    .frame(width: sidebarWidth)
                    .background(Theme.sidebar)
                    .transition(.move(edge: .leading).combined(with: .opacity))
                SidebarResizer(width: $sidebarWidth) {
                    withAnimation(.easeInOut(duration: 0.2)) { sidebarVisible = false }
                }
                .zIndex(1)
            }
            DetailView()
        }
        .background(Theme.content)
        .clipShape(shape)
        .overlay(shape.stroke(Theme.hairline, lineWidth: 1))
    }

    private var detailLeading: CGFloat {
        Self.railWidth + (sidebarVisible ? sidebarWidth + 1 : 0)
    }
}

/// ⌘K switcher: type to find any agent, shell or workspace in the current session.
/// ↑/↓ move, Return opens, Esc or a click outside closes.
private struct CommandPalette: View {
    @Environment(HerdrStore.self) private var store
    let initialQuery: String
    let close: () -> Void
    @State private var query = ""
    @State private var highlighted = 0
    @FocusState private var focused: Bool

    private struct Item: Identifiable {
        enum Target { case pane(String), workspace(Workspace) }
        let id: String
        let title: String
        let subtitle: String
        let pane: Pane?
        let target: Target
    }

    /// Agents that need you first, then other agents, shells, and workspaces last.
    private var allItems: [Item] {
        let panes = store.panes.sorted { rank($0) < rank($1) }.map { pane in
            Item(
                id: pane.paneId,
                title: pane.displayName,
                subtitle: [pane.kind, store.workspaceTitle(id: pane.workspaceId)].compactMap { $0 }.joined(separator: " · "),
                pane: pane,
                target: .pane(pane.paneId)
            )
        }
        let workspaces = store.workspaces.map { ws in
            Item(id: "ws:" + ws.workspaceId, title: store.title(of: ws), subtitle: "Workspace", pane: nil, target: .workspace(ws))
        }
        return panes + workspaces
    }

    private func rank(_ pane: Pane) -> Int {
        if pane.agentStatus.needsAttention { return 0 }
        return pane.isAgent ? 1 : 2
    }

    private var items: [Item] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return allItems }
        return allItems.enumerated()
            .compactMap { offset, item in Self.score(q, item.title, item.subtitle).map { ($0, offset, item) } }
            .sorted { ($0.0, $0.1) < ($1.0, $1.1) }
            .map(\.2)
    }

    /// Lower is better: title prefix, word prefix in the title, anywhere in the title,
    /// anywhere in the subtitle, then letters in order. Nil means no match.
    static func score(_ q: String, _ title: String, _ subtitle: String) -> Int? {
        let t = title.lowercased()
        if t.hasPrefix(q) { return 0 }
        if t.split(whereSeparator: { !$0.isLetter && !$0.isNumber }).contains(where: { $0.hasPrefix(q) }) { return 1 }
        if t.contains(q) { return 2 }
        if subtitle.lowercased().contains(q) { return 3 }
        var rest = Substring(q)
        for c in t where c == rest.first { rest = rest.dropFirst() }
        return rest.isEmpty ? 4 : nil
    }

    var body: some View {
        let results = items
        ZStack(alignment: .top) {
            Color.black.opacity(0.25)
                .ignoresSafeArea()
                .onTapGesture(perform: close)

            VStack(spacing: 0) {
                HStack(spacing: 10) {
                    PhIcon(.search, size: 15).foregroundStyle(Theme.text3)
                    TextField("Jump to an agent, shell or workspace", text: $query)
                        .textFieldStyle(.plain)
                        .font(.system(size: 16))
                        .focused($focused)
                        .onSubmit { open(results) }
                        .onExitCommand(perform: close)
                        .onKeyPress(.downArrow) { move(1, in: results); return .handled }
                        .onKeyPress(.upArrow) { move(-1, in: results); return .handled }
                }
                .padding(.horizontal, 16)
                .frame(height: 50)

                Theme.hairline.frame(height: 1)

                if results.isEmpty {
                    Text(store.panes.isEmpty && store.workspaces.isEmpty ? "Nothing in this session yet." : "No matches.")
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.text3)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 18)
                } else {
                    ScrollViewReader { proxy in
                        ScrollView {
                            VStack(spacing: 2) {
                                ForEach(Array(results.enumerated()), id: \.element.id) { index, item in
                                    row(item, selected: index == highlighted)
                                        .id(item.id)
                                        .onTapGesture { open(item) }
                                        .pointerCursor()
                                }
                            }
                            .padding(6)
                        }
                        .frame(height: min(CGFloat(results.count) * 38 + 12, 340))
                        .onChange(of: highlighted) { _, index in
                            if results.indices.contains(index) { proxy.scrollTo(results[index].id) }
                        }
                    }
                }
            }
            .frame(width: 560)
            .background(RoundedRectangle(cornerRadius: 14).fill(Theme.card))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.hairline))
            .shadow(color: .black.opacity(0.35), radius: 30, y: 12)
            .padding(.top, 90)
        }
        .onAppear {
            query = initialQuery
            focused = true
        }
        .onChange(of: query) { highlighted = 0 }
    }

    private func row(_ item: Item, selected: Bool) -> some View {
        HStack(spacing: 10) {
            Group {
                if let pane = item.pane {
                    if pane.isAgent { StatusGlyph(status: pane.agentStatus) } else { PhIcon(.terminal, size: 12) }
                } else {
                    PhIcon(.folder, size: 12)
                }
            }
            .font(.system(size: 12))
            .foregroundStyle(Theme.text2)
            .frame(width: 18)
            Text(item.title).font(.system(size: 14)).foregroundStyle(Theme.text).lineLimit(1)
            Text(item.subtitle).font(.system(size: 12)).foregroundStyle(Theme.text3).lineLimit(1)
            Spacer(minLength: 8)
            if selected { Text("↩").font(.system(size: 12)).foregroundStyle(Theme.text3) }
        }
        .padding(.horizontal, 10)
        .frame(height: 36)
        .background(RoundedRectangle(cornerRadius: 8).fill(selected ? Theme.washStrong : .clear))
        .contentShape(Rectangle())
    }

    private func move(_ step: Int, in results: [Item]) {
        guard !results.isEmpty else { return }
        highlighted = (highlighted + step + results.count) % results.count
    }

    private func open(_ results: [Item]) {
        guard results.indices.contains(highlighted) else { return }
        open(results[highlighted])
    }

    /// Panes open in the detail view. A workspace opens its first agent, or its first shell.
    private func open(_ item: Item) {
        switch item.target {
        case .pane(let id):
            store.selectedPaneId = id
        case .workspace(let ws):
            let panes = store.panes(in: ws)
            store.selectedPaneId = (panes.first(where: \.isAgent) ?? panes.first)?.paneId
        }
        store.sidebarMode = .home
        close()
    }
}

/// The sidebar's right edge. Drag to resize between 220 and 480 pt; drag well past the
/// minimum and the sidebar closes, like Finder and Xcode. ⌘B or the toolbar button brings it back
/// at its last width.
private struct SidebarResizer: View {
    @Binding var width: Double
    let collapse: () -> Void
    @State private var startWidth: Double?
    @State private var hovering = false

    static let range = 220.0...480.0
    static let collapseBelow = 150.0

    var body: some View {
        Theme.hairline
            .frame(width: 1)
            .overlay {
                ResizeHighlight(active: hovering || startWidth != nil, vertical: true)
                Color.clear
                    .frame(width: 9)
                    .contentShape(Rectangle())
                    .onHover { inside in
                        guard inside != hovering else { return }
                        hovering = inside
                        if inside { NSCursor.resizeLeftRight.push() } else { NSCursor.pop() }
                    }
                    .gesture(drag)
            }
            .onDisappear {
                if hovering { NSCursor.pop() }
                hovering = false
            }
            .accessibilityElement()
            .accessibilityLabel("Sidebar width")
            .accessibilityValue("\(Int(width)) points")
            .accessibilityAdjustableAction { direction in
                switch direction {
                case .increment: width = min(width + 20, Self.range.upperBound)
                case .decrement: width = max(width - 20, Self.range.lowerBound)
                @unknown default: break
                }
            }
    }

    private var drag: some Gesture {
        DragGesture(minimumDistance: 1, coordinateSpace: .global)
            .onChanged { value in
                let start = startWidth ?? width
                startWidth = start
                let proposed = start + value.translation.width
                if proposed < Self.collapseBelow {
                    startWidth = nil
                    collapse()
                } else {
                    width = min(max(proposed, Self.range.lowerBound), Self.range.upperBound)
                }
            }
            .onEnded { _ in startWidth = nil }
    }
}
