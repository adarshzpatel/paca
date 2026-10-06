import AppKit
import HerdrKit
import PacaTheme
import SwiftUI

/// Codex-style top row: sidebar toggle by the traffic lights, open panes as tabs from the
/// content column, then the selected pane's folder and the theme menu on the right.
struct TopBar: View {
    @Environment(HerdrStore.self) private var store
    @Binding var sidebarVisible: Bool
    /// Where the content column starts, so tabs line up with it like Codex.
    let contentLeading: CGFloat

    static let height: CGFloat = 40
    /// Traffic lights plus the 26pt sidebar toggle.
    private static let leadingControls: CGFloat = Theme.trafficLightInset + 26

    var body: some View {
        HStack(spacing: 0) {
            Spacer().frame(width: Theme.trafficLightInset)
            IconButton(icon: .sidebar, help: sidebarVisible ? "Hide sidebar" : "Show sidebar", shortcut: "⌘B") {
                withAnimation(.easeInOut(duration: 0.2)) { sidebarVisible.toggle() }
            }

            if sidebarVisible {
                // The sidebar's edge hairline sits 1pt before `contentLeading`; this one continues it.
                Spacer().frame(width: max(8, contentLeading - 1 - Self.leadingControls))
                Theme.hairline.frame(width: 1, height: 20)
                Spacer().frame(width: 8)
            } else {
                Spacer().frame(width: 10)
            }

            TabStrip()

            Spacer(minLength: 12)

            SplitButton()
            if let pane = store.pane(id: store.selectedPaneId), let cwd = pane.foregroundCwd ?? pane.cwd {
                FolderChip(path: cwd, revealable: !store.isRemote)
            }
        }
        .padding(.trailing, 12)
        .frame(height: Self.height)
    }
}

private struct TabStrip: View {
    @Environment(HerdrStore.self) private var store

    var body: some View {
        strip.background(shortcuts)
    }

    /// ⌘1…⌘9 jump to a tab. ⌘D / ⌘⇧D live in `AppShortcuts`.
    private var shortcuts: some View {
        ZStack {
            ForEach(Array(store.tabs.prefix(9).enumerated()), id: \.element.id) { index, pane in
                Button("") { store.selectedPaneId = pane.paneId }
                    .keyboardShortcut(KeyEquivalent(Character("\(index + 1)")), modifiers: .command)
            }
        }
        .hidden()
        .accessibilityHidden(true)
    }

    private var strip: some View {
        ScrollViewReader { proxy in
        ScrollView(.horizontal) {
            HStack(spacing: 2) {
                let tabs = store.tabs
                ForEach(Array(tabs.enumerated()), id: \.element.id) { index, pane in
                    if index > 0 {
                        // Separator between two unselected tabs; hidden next to the selected one.
                        let quiet = pane.paneId != store.selectedPaneId && tabs[index - 1].paneId != store.selectedPaneId
                        Theme.hairline.frame(width: 1, height: 14).opacity(quiet ? 1 : 0)
                    }
                    PaneTab(pane: pane, selected: pane.paneId == store.selectedPaneId,
                            visible: store.splitAxis != nil && store.slots.contains(pane.paneId))
                        .id(pane.paneId)
                }
                IconButton(icon: .plus, help: "New agent in this workspace") {
                    store.newAgentRequest = .init(workspace: store.pane(id: store.selectedPaneId).flatMap { store.workspace(id: $0.workspaceId) })
                }
            }
            .padding(.vertical, 2)
            .scrollFadeContent()
        }
        // Keep the selected tab on screen, including one picked from the sidebar or ⌘1…⌘9.
        .onAppear { reveal(store.selectedPaneId, with: proxy, animated: false) }
        .onChange(of: store.selectedPaneId) { _, id in reveal(id, with: proxy, animated: true) }
        // A tab can be selected before herdr reports its pane; scroll once it appears.
        .onChange(of: store.tabs.map(\.paneId)) { _, _ in reveal(store.selectedPaneId, with: proxy, animated: false) }
        .scrollIndicators(.never)
        .fixedSize(horizontal: false, vertical: true)
        // Resizing the window can push the selected tab out of view.
        .scrollFade(.horizontal) { _ in reveal(store.selectedPaneId, with: proxy, animated: false) }
        }
    }

    private func reveal(_ id: String?, with proxy: ScrollViewProxy, animated: Bool) {
        guard let id else { return }
        // After layout settles, so a tab that was just opened or a resize has been laid out.
        // Centered: with a nil anchor, macOS sometimes judges the tab visible when it isn't.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            withAnimation(animated ? .easeOut(duration: 0.2) : nil) { proxy.scrollTo(id, anchor: .center) }
        }
    }
}

private struct PaneTab: View {
    @Environment(HerdrStore.self) private var store

    /// Full name, workspace, status and folder: the tab itself truncates all of them.
    private var tabTip: String {
        var lines = [pane.displayName]
        let meta = [store.workspaceTitle(id: pane.workspaceId), pane.kind, pane.isAgent ? pane.agentStatus.title : nil]
            .compactMap { $0 }
        if !meta.isEmpty { lines.append(meta.joined(separator: " · ")) }
        if let cwd = pane.foregroundCwd ?? pane.cwd { lines.append((cwd as NSString).abbreviatingWithTildeInPath) }
        return lines.joined(separator: "\n")
    }
    let pane: Pane
    let selected: Bool
    /// On screen in the other side of a split.
    var visible = false
    @State private var hovered = false

    var body: some View {
        HStack(spacing: 7) {
            Group {
                if pane.isAgent {
                    StatusGlyph(status: pane.agentStatus, size: 12)
                } else {
                    PhIcon(.terminal, size: 11.5)
                        .foregroundStyle(Theme.text2)
                }
            }
            .frame(width: 14)

            if let ws = store.workspace(id: pane.workspaceId) { WorkspacePill(workspace: ws, bare: true) }

            Text(pane.displayName)
                .font(.system(size: 13, weight: selected ? .medium : .regular))
                .foregroundStyle(selected || visible ? Theme.text : Theme.text2)
                .lineLimit(1)
                .frame(maxWidth: 180, alignment: .leading)

            Button { store.closeTab(pane.paneId) } label: {
                PhIcon(.x, size: 9.5)
                    .foregroundStyle(Theme.text3)
                    .frame(width: 22, height: 22)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .pointerCursor()
            .opacity(selected || hovered ? 1 : 0)
            .hoverTip("Close tab (the pane keeps running)")
            .accessibilityLabel("Close \(pane.displayName) tab")
        }
        .padding(.leading, 10)
        .padding(.trailing, 3)
        .frame(height: 30)
        // The selected tab takes the content panel's color, so it reads as the page below it.
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(selected ? Theme.content : visible || hovered ? Theme.wash : .clear)
        )
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(selected ? Theme.hairline : .clear))
        .shadow(color: .black.opacity(selected ? 0.18 : 0), radius: 2, y: 1)
        .contentShape(Rectangle())
        .onTapGesture { store.selectedPaneId = pane.paneId }
        .onHover { hovered = $0 }
        .pointerCursor()
        .hoverTip(tabTip)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(pane.isAgent ? "\(pane.displayName), \(pane.agentStatus.title ?? "idle")" : pane.displayName)
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
        .accessibilityAction { store.selectedPaneId = pane.paneId }
        .accessibilityAction(named: "Close tab") { store.closeTab(pane.paneId) }
    }
}

/// The selected pane's working directory. Click opens it in Finder (local sessions only).
private struct FolderChip: View {
    let path: String
    let revealable: Bool
    @State private var hovered = false

    var body: some View {
        Button {
            NSWorkspace.shared.open(URL(fileURLWithPath: path))
        } label: {
            HStack(spacing: 6) {
                PhIcon(.folder, size: 11.5)
                Text(Self.short(path))
                    .font(.system(size: 12))
                    .lineLimit(1)
            }
            .foregroundStyle(hovered && revealable ? Theme.text : Theme.text3)
            .padding(.horizontal, 8)
            .frame(height: 26)
            .background(RoundedRectangle(cornerRadius: 7).fill(hovered && revealable ? Theme.wash : .clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!revealable)
        .onHover { hovered = $0 }
        .pointerCursor()
        .hoverTip(revealable ? "Open \((path as NSString).abbreviatingWithTildeInPath) in Finder" : path)
    }

    /// `~/a/b/c/d` keeps the last three folders: `…/b/c/d`.
    static func short(_ path: String) -> String {
        let tilde = (path as NSString).abbreviatingWithTildeInPath
        let parts = tilde.split(separator: "/", omittingEmptySubsequences: false)
        guard parts.count > 4 else { return tilde }
        return "…/" + parts.suffix(3).joined(separator: "/")
    }
}

/// Theme picker, same list as ⌘,.
struct ThemeMenu: View {
    var size: CGFloat = 26
    var fontSize: CGFloat = 13
    var tipEdge: Edge = .bottom

    var body: some View {
        @Bindable var themes = ThemeStore.shared
        Menu {
            ThemeChoicePicker(choice: $themes.choice)
            Divider()
            Button("Open Themes Folder") { ThemeStore.openUserThemesFolder() }
        } label: {
            PhIcon(.palette, size: fontSize)
                .foregroundStyle(Theme.text3)
                .frame(width: size, height: size)
                .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .pointerCursor()
        .hoverTip("Theme: \(themes.scheme.name)", edge: tipEdge)
        .accessibilityLabel("Theme")
    }
}

/// Match herdr, match macOS, or one fixed scheme. Each scheme shows a swatch of its colors.
struct ThemeChoicePicker: View {
    @Binding var choice: String

    var body: some View {
        let themes = ThemeStore.shared
        Picker("Theme", selection: $choice) {
            Text("Match herdr (\(themes.herdrActive))").tag(ThemeStore.matchHerdr)
            Text("Match System (Paca Light / Dark)").tag(ThemeStore.matchSystem)
            if let name = themes.ghosttyThemeName {
                Text("Match Ghostty (\(name))").tag(ThemeStore.matchGhostty)
            }
            Divider()
            ForEach(themes.all) { scheme in
                Label { Text(scheme.name) } icon: { Image(nsImage: ThemeSwatch.image(scheme)) }
                    .tag(scheme.id)
            }
        }
        .pickerStyle(.inline)
    }
}

enum ThemeSwatch {
    /// Background with three accent dots, for menus and settings.
    static func image(_ scheme: Base16Scheme) -> NSImage {
        let size = NSSize(width: 30, height: 14)
        let image = NSImage(size: size, flipped: false) { rect in
            let card = NSBezierPath(roundedRect: rect.insetBy(dx: 0.5, dy: 0.5), xRadius: 4, yRadius: 4)
            Theme.rgb(scheme[0x00]).setFill()
            card.fill()
            Theme.rgb(scheme[0x05], 0.25).setStroke()
            card.stroke()
            for (index, slot) in [0x0D, 0x0E, 0x0B].enumerated() {
                Theme.rgb(scheme[slot]).setFill()
                NSBezierPath(ovalIn: NSRect(x: 5 + CGFloat(index) * 8, y: 4, width: 6, height: 6)).fill()
            }
            return true
        }
        image.isTemplate = false
        return image
    }
}

/// Split right, split down, or close the split. Same as ⌘D / ⌘⇧D.
private struct SplitButton: View {
    @Environment(HerdrStore.self) private var store

    var body: some View {
        Menu {
            Button("Split Right") { store.toggleSplit(.horizontal) }
                .disabled(store.splitAxis == .horizontal)
            Button("Split Down") { store.toggleSplit(.vertical) }
                .disabled(store.splitAxis == .vertical)
            if store.splitAxis != nil {
                Divider()
                Button("Close Split") { store.closeSplit() }
            }
        } label: {
            PhIcon(store.splitAxis == .vertical ? .rows : .columns, size: 13)
                .foregroundStyle(store.splitAxis != nil ? Theme.accent : Theme.text3)
                .frame(width: 28, height: 26)
                .contentShape(Rectangle())
        } primaryAction: {
            store.toggleSplit(store.splitAxis ?? .horizontal)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .pointerCursor()
        .disabled(store.selectedPaneId == nil && store.splitAxis == nil)
        .hoverTip(store.splitAxis == nil ? "Split right · hold for more" : "Close split",
                  shortcut: store.splitAxis == .vertical ? "⌘⇧D" : "⌘D")
        .accessibilityLabel(store.splitAxis == nil ? "Split" : "Close split")
    }
}

/// App shortcuts matched by physical key, so ⌘D and ⌘⇧D can't be confused (SwiftUI's
/// `keyboardShortcut` treated Shift+D as plain ⌘D in testing).
@MainActor
enum AppShortcuts {
    static weak var store: HerdrStore?
    private static var monitor: Any?

    static func install(store: HerdrStore) {
        self.store = store
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            MainActor.assumeIsolated { handle(event) } ? nil : event
        }
    }

    /// True when the event was a Paca shortcut and has been handled.
    static func handle(_ event: NSEvent) -> Bool {
        guard let store else { return false }
        let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask).subtracting([.capsLock, .numericPad, .function])
        switch (event.keyCode, mods) {
        case (2, [.command]): store.toggleSplit(.horizontal)           // ⌘D
        case (2, [.command, .shift]): store.toggleSplit(.vertical)     // ⌘⇧D
        default: return false
        }
        return true
    }
}

