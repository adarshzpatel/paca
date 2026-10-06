import AppKit
import HerdrKit
import SwiftUI

struct Sidebar: View {
    @Environment(HerdrStore.self) private var store
    @State private var collapsed: Set<String> = []
    @State private var showAll: Set<String> = []
    @State private var searching = false
    @State private var query = ""
    @FocusState private var searchFocused: Bool
    @State private var renamingId: String?
    @State private var renameText = ""
    @State private var closing: Workspace?
    @State private var closingPane: Pane?
    @State private var worktreesOf: Workspace?
    @State private var removingWorktree: Workspace?
    @State private var dirtyWorktree: Workspace?
    @State private var dirtyFiles: [String] = []
    @State private var askingRemotePath = false
    @State private var remotePath = ""

    private static let visibleChildren = 5
    /// Child icons line up under the folder's name; the rail runs down the folder icon's center.
    static let childIndent: CGFloat = 2 * Theme.space + Sidebar.iconBox
    /// Center of the right-hand column, from the row's trailing edge. Status glyphs, counts and
    /// the + buttons all sit on it so they line up down the sidebar.
    static let trailingColumn: CGFloat = 14
    /// Every row icon sits in this box with `Theme.space` before its text, so icon-to-text
    /// gaps match on every row. 13.5pt Phosphor icons render at 16pt.
    static let iconBox: CGFloat = 16
    /// Height of every one-line sidebar row.
    static let rowHeight: CGFloat = 28

    var body: some View {
        worktreeDialogs(sheets(closeDialogs(column)))
    }

    // MARK: Dialogs

    private func closeDialogs(_ content: some View) -> some View {
        content
            .confirmationDialog(
                closing.map { "Close \(store.title(of: $0))?" } ?? "",
                isPresented: Binding(get: { closing != nil }, set: { if !$0 { closing = nil } }),
                presenting: closing
            ) { ws in
                Button("Close Workspace", role: .destructive) {
                    Task { await store.closeWorkspace(ws) }
                }
            } message: { ws in
                Text(closeWarning(for: ws))
            }
            .confirmationDialog(
                closingPane.map { "Close \($0.displayName)?" } ?? "",
                isPresented: Binding(get: { closingPane != nil }, set: { if !$0 { closingPane = nil } }),
                presenting: closingPane
            ) { pane in
                Button("Close", role: .destructive) {
                    Task { await store.close(pane) }
                }
            } message: { pane in
                Text("\(pane.displayName) is \(pane.agentStatus == .blocked ? "waiting for you" : "working"). Closing stops it and loses whatever it hasn't saved.")
            }
    }

    private func sheets(_ content: some View) -> some View {
        content
            .alert("New workspace on \(store.targetName)", isPresented: $askingRemotePath) {
                TextField("Path", text: $remotePath, prompt: Text("/home/me/project"))
                Button("Cancel", role: .cancel) {}
                Button("Create") { Task { await store.createWorkspace(atPath: remotePath) } }
            } message: {
                Text("Full path of a folder on \(store.targetName).")
            }
            .sheet(item: $worktreesOf) { ws in
                WorktreeSheet(workspace: ws)
            }
    }

    private func worktreeDialogs(_ content: some View) -> some View {
        content
            .confirmationDialog(
                removingWorktree.map { "Remove the \($0.label) worktree?" } ?? "",
                isPresented: Binding(get: { removingWorktree != nil }, set: { if !$0 { removingWorktree = nil } }),
                presenting: removingWorktree
            ) { ws in
                Button("Remove Worktree", role: .destructive) { removeWorktree(ws, force: false) }
            } message: { ws in
                Text("This deletes the checkout\(ws.worktree?.checkoutPath.map { " at \($0)" } ?? "") and closes the workspace. The branch stays in the repo.")
            }
            .confirmationDialog(
                dirtyWorktree.map { "\($0.label) has uncommitted changes" } ?? "",
                isPresented: Binding(get: { dirtyWorktree != nil }, set: { if !$0 { dirtyWorktree = nil } }),
                presenting: dirtyWorktree
            ) { ws in
                Button("Delete Changes and Remove", role: .destructive) { removeWorktree(ws, force: true) }
            } message: { _ in
                Text(dirtyFiles.isEmpty
                     ? "Removing it anyway deletes those changes for good."
                     : "Removing it anyway deletes these for good:\n" + dirtyFiles.joined(separator: "\n"))
            }
    }

    private var column: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            if searching { searchField }

            ScrollView {
                VStack(alignment: .leading, spacing: 1) {
                    if searching && !query.isEmpty {
                        searchResults
                    } else if store.sidebarMode == .inbox {
                        inbox
                    } else if store.sidebarMode == .activity {
                        ActivityList()
                    } else {
                        home
                    }
                }
                .padding(.horizontal, Theme.space)
                .padding(.bottom, 16)
                .scrollFadeContent()
            }
            .scrollIndicators(.never)
            .scrollFade(.vertical)

            if let error = store.actionError {
                ErrorBanner(text: error) { store.actionError = nil }
            }

        }
    }

    // MARK: Sections

    private var header: some View {
        HStack(spacing: 4) {
            BrandLockup()
            Spacer()
            IconButton(icon: .search, help: "Filter agents and shells") {
                searching.toggle()
                query = ""
                searchFocused = searching
            }
        }
        .padding(.leading, 2 * Theme.space)
        .padding(.trailing, Theme.space + Self.trailingColumn - 13)
        // Puts the visible top of the brand lockup 2 * space from the panel edge, matching the
        // icons' left inset. The lockup is vertically centered against the 24pt search button,
        // which takes ~3pt off the visible gap.
        .padding(.top, 2 * Theme.space + 1)
        .padding(.bottom, Theme.space)
    }

    private var searchField: some View {
        HStack(spacing: 6) {
            PhIcon(.search, size: 11).foregroundStyle(Theme.text3)
            TextField("Filter agents and shells", text: $query)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .focused($searchFocused)
                .onExitCommand { searching = false; query = "" }
        }
        .padding(.horizontal, Theme.space)
        .frame(height: 28)
        .background(RoundedRectangle(cornerRadius: 8).fill(Theme.wash))
        .padding(.horizontal, Theme.space)
        .padding(.bottom, 10)
    }

    @ViewBuilder
    private var home: some View {
        ActionRow(
            icon: .tray,
            title: "Needs you",
            badge: store.needsYou.count
        ) { store.sidebarMode = .inbox }

        ActionRow(icon: .plusCircle, title: "New agent") { openNewAgent(in: nil) }

        HStack(spacing: 0) {
            SectionLabel(title: "Workspaces")
            Spacer()
            IconButton(icon: .plus, help: "New workspace from a folder", action: pickFolder)
        }
        .padding(.top, 4)
        .padding(.trailing, Self.trailingColumn - 13)

        if store.workspaces.isEmpty {
            Hint(text: store.connectionError == nil ? "No workspaces yet" : store.isRemote ? store.connectionError ?? "" : "Waiting for herdr…")
        }
        ForEach(store.workspaces) { ws in
            let isOpen = !collapsed.contains(ws.workspaceId)
            if renamingId == ws.workspaceId {
                RenameField(text: $renameText, icon: .folder) { commit in
                    renamingId = nil
                    if commit { Task { await store.renameWorkspace(ws, to: renameText) } }
                }
            } else {
                WorkspaceRow(workspace: ws, open: isOpen, toggle: { toggle(ws.workspaceId) }, newAgent: { openNewAgent(in: ws) })
                    .contextMenu {
                        Button("New Agent…") { openNewAgent(in: ws) }
                        Button("New Shell") { Task { await store.newShell(in: ws) } }
                        Button("Worktrees…") { worktreesOf = ws }
                        Divider()
                        Button("Rename…") { startRename(ws) }
                        colorMenu(ws)
                        Divider()
                        if ws.isLinkedWorktree {
                            Button("Remove Worktree…", role: .destructive) { removingWorktree = ws }
                        }
                        Button("Close Workspace…", role: .destructive) { requestClose(ws) }
                    }
                    .draggable(ws.workspaceId)
                    .dropDestination(for: String.self) { ids, _ in
                        drop(ids, onto: ws)
                    }
            }

            if isOpen {
                let panes = store.panes(in: ws)
                let expanded = showAll.contains(ws.workspaceId)
                let shown = expanded ? panes : Array(panes.prefix(Self.visibleChildren))
                let hasMore = panes.count > Self.visibleChildren
                // No spacing, so each row's branch meets the next one's.
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(shown) { pane in
                        paneRow(pane, indent: Self.childIndent)
                            .overlay(alignment: .leading) {
                                TreeBranch(last: !hasMore && pane.id == shown.last?.id)
                            }
                    }
                    if hasMore {
                        Button { toggleShowAll(ws.workspaceId) } label: {
                            Text(expanded ? "Show less" : "+\(panes.count - Self.visibleChildren) more")
                                .font(.system(size: 12.5))
                                .foregroundStyle(Theme.text3)
                                .padding(.leading, Self.childIndent)
                                .frame(maxWidth: .infinity, minHeight: 24, alignment: .leading)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .pointerCursor()
                        .overlay(alignment: .leading) { TreeBranch(last: true) }
                    }
                }
            }
            Spacer().frame(height: 4)
        }
    }

    @ViewBuilder
    private var inbox: some View {
        SectionLabel(title: "Needs you")
        if store.needsYou.isEmpty {
            Hint(text: "Nothing needs you right now.")
        }
        ForEach(store.needsYou) { pane in
            paneRow(pane, subtitle: store.workspaceTitle(id: pane.workspaceId))
        }
    }

    @ViewBuilder
    private var searchResults: some View {
        let q = query.lowercased()
        let hits = store.panes.filter { pane in
            [pane.displayName, pane.kind ?? "", store.workspaceTitle(id: pane.workspaceId) ?? ""]
                .contains { $0.lowercased().contains(q) }
        }
        SectionLabel(title: "\(hits.count) match\(hits.count == 1 ? "" : "es")")
        ForEach(hits) { pane in
            paneRow(pane, subtitle: store.workspaceTitle(id: pane.workspaceId))
        }
    }

    private func toggle(_ id: String) {
        withAnimation(.easeOut(duration: 0.15)) {
            if collapsed.contains(id) { collapsed.remove(id) } else { collapsed.insert(id) }
        }
    }

    private func toggleShowAll(_ id: String) {
        if showAll.contains(id) { showAll.remove(id) } else { showAll.insert(id) }
    }

    // MARK: Pane actions

    @ViewBuilder
    private func paneRow(_ pane: Pane, subtitle: String? = nil, indent: CGFloat = Theme.space) -> some View {
        if renamingId == pane.paneId {
            RenameField(text: $renameText, icon: pane.isAgent ? .sparkle : .terminal) { commit in
                renamingId = nil
                if commit { Task { await store.rename(pane, to: renameText) } }
            }
            .padding(.leading, indent - Theme.space)
        } else {
            PaneRow(pane: pane, subtitle: subtitle, indent: indent)
                .contextMenu {
                    Button(pane.agentLaunchPending ? "Rename (after it starts)" : "Rename…") {
                        renameText = pane.displayName
                        renamingId = pane.paneId
                    }
                    .disabled(pane.agentLaunchPending)
                    Divider()
                    Button("Split Right") { Task { await store.split(pane, .right) } }
                    Button("Split Down") { Task { await store.split(pane, .down) } }
                    Divider()
                    Button("Show in herdr") { Task { await store.showInHerdr(pane) } }
                    Divider()
                    Button(pane.isAgent ? "Close Agent…" : "Close Shell", role: .destructive) { requestClose(pane) }
                }
        }
    }

    /// Folder color picker with a swatch per choice; Automatic goes back to the hashed tint.
    private func colorMenu(_ ws: Workspace) -> some View {
        let colors = WorkspaceColors.shared
        let scope = store.workspaceScope
        let picked = Binding<Int?>(
            get: { colors.slot(for: ws.workspaceId, scope: scope) },
            set: { colors.set($0, for: ws.workspaceId, scope: scope) }
        )
        return Menu("Color") {
            Picker("Color", selection: picked) {
                Text("Automatic").tag(Int?.none)
                Divider()
                ForEach(WorkspaceColors.choices, id: \.slot) { choice in
                    Label {
                        Text(choice.name)
                    } icon: {
                        Image(nsImage: WorkspaceColors.swatch(Theme.workspaceTintNS(slot: choice.slot)))
                    }
                    .tag(Int?.some(choice.slot))
                }
            }
            .pickerStyle(.inline)
            .labelsHidden()
        }
    }

    /// Only a busy agent asks first. Idle agents and shells close straight away.
    private func requestClose(_ pane: Pane) {
        if pane.isAgent && (pane.agentStatus == .working || pane.agentStatus == .blocked) {
            closingPane = pane
        } else {
            Task { await store.close(pane) }
        }
    }

    private func removeWorktree(_ ws: Workspace, force: Bool) {
        Task {
            if await store.removeWorktree(ws, force: force) == .dirty {
                dirtyFiles = store.uncommittedFiles(in: ws)
                dirtyWorktree = ws
            }
        }
    }

    private func openNewAgent(in ws: Workspace?) {
        store.newAgentRequest = .init(workspace: ws)
    }

    // MARK: Workspace actions

    /// Local sessions pick a folder in Finder's panel. On a machine the folder lives over
    /// there, so its path is typed instead.
    private func pickFolder() {
        if store.isRemote {
            remotePath = ""
            askingRemotePath = true
            return
        }
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Create Workspace"
        panel.message = "Choose the folder this workspace runs in."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        Task { await store.createWorkspace(at: url) }
    }

    private func startRename(_ ws: Workspace) {
        renameText = ws.label
        renamingId = ws.workspaceId
    }

    /// Closing kills every pane, so ask first whenever an agent lives there.
    private func requestClose(_ ws: Workspace) {
        if store.panes(in: ws).contains(where: \.isAgent) {
            closing = ws
        } else {
            Task { await store.closeWorkspace(ws) }
        }
    }

    private func closeWarning(for ws: Workspace) -> String {
        let busy = store.busyAgents(in: ws).count
        let agents = store.panes(in: ws).filter(\.isAgent).count
        let detail = busy > 0 ? "\(busy) of them \(busy == 1 ? "is" : "are") mid-task." : "None of them are mid-task."
        return "This stops \(agents) agent\(agents == 1 ? "" : "s") and closes every shell in it. \(detail)"
    }

    /// Dropping a workspace on another puts it in that one's place.
    private func drop(_ ids: [String], onto target: Workspace) -> Bool {
        guard let id = ids.first, id != target.workspaceId,
              store.workspace(id: id) != nil,
              let index = store.workspaces.firstIndex(where: { $0.workspaceId == target.workspaceId })
        else { return false }
        Task { await store.moveWorkspace(id, to: index) }
        return true
    }
}

// MARK: - Rows

/// Tree connector in a child row's indent: the workspace rail runs down the folder icon's center and curves
/// into the row's icon. The last row stops at the curve, closing the group.
private struct TreeBranch: View {
    let last: Bool

    var body: some View {
        Canvas { context, size in
            let x = Theme.space + Sidebar.iconBox / 2, end = Sidebar.childIndent - 3, radius: CGFloat = 7
            let mid = size.height / 2
            var path = Path()
            path.move(to: CGPoint(x: x, y: 0))
            path.addLine(to: CGPoint(x: x, y: mid - radius))
            path.addQuadCurve(to: CGPoint(x: x + radius, y: mid), control: CGPoint(x: x, y: mid))
            path.addLine(to: CGPoint(x: end, y: mid))
            if !last {
                path.move(to: CGPoint(x: x, y: mid - radius))
                path.addLine(to: CGPoint(x: x, y: size.height))
            }
            context.stroke(path, with: .color(Theme.text4.opacity(0.8)), style: StrokeStyle(lineWidth: 1.25, lineCap: .round))
        }
        .frame(width: Sidebar.childIndent)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

private struct SectionLabel: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.system(size: 11, weight: .semibold))
            .textCase(.uppercase)
            .tracking(0.6)
            .foregroundStyle(Theme.text4)
            .padding(.horizontal, Theme.space)
            .frame(height: 24, alignment: .leading)
    }
}

private struct Hint: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 12.5))
            .foregroundStyle(Theme.text3)
            .padding(.horizontal, Theme.space)
            .padding(.vertical, 6)
    }
}

/// Inline editor that stands in for a row while renaming. Return or clicking away saves, Escape cancels.
private struct RenameField: View {
    @Binding var text: String
    let icon: Icon
    let finish: (_ commit: Bool) -> Void
    @FocusState private var focused: Bool
    @State private var done = false

    var body: some View {
        HStack(spacing: Theme.space) {
            PhIcon(icon, size: 13.5)
                .foregroundStyle(Theme.text2)
                .frame(width: Sidebar.iconBox)
            TextField("Name", text: $text)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .focused($focused)
                .onSubmit { end(true) }
                .onExitCommand { end(false) }
        }
        .padding(.horizontal, Theme.space)
        .frame(height: Sidebar.rowHeight)
        .background(RoundedRectangle(cornerRadius: 8).fill(Theme.wash))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.accent.opacity(0.6)))
        .onAppear { focused = true }
        .onChange(of: focused) { _, isFocused in
            if !isFocused { end(true) }
        }
    }

    private func end(_ commit: Bool) {
        guard !done else { return }
        done = true
        finish(commit)
    }
}

/// Picks a workspace, an agent kind and a name, then starts the agent in a new tab.
struct NewAgentSheet: View {
    @Environment(HerdrStore.self) private var store
    @Environment(\.dismiss) private var dismissSheet
    let initialWorkspace: Workspace?
    /// Set when shown in a QuickModal; otherwise it closes like a sheet.
    var onClose: (() -> Void)?
    @FocusState private var nameFocused: Bool

    private func dismiss() {
        if let onClose { onClose() } else { dismissSheet() }
    }

    @State private var workspaceId = ""
    @State private var kind = ""
    @State private var name = ""
    @State private var starting = false
    @State private var error: String?
    @State private var onWorktree = false
    @State private var branch = ""

    private var kinds: [String] { store.agentKinds.isEmpty ? ["claude", "codex"] : store.agentKinds }
    private var canStart: Bool { !starting && store.workspace(id: workspaceId) != nil && !kind.isEmpty }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("New agent").font(.system(size: 15, weight: .semibold))

            Form {
                Picker("Workspace", selection: $workspaceId) {
                    ForEach(store.workspaces) { ws in
                        Text(store.title(of: ws)).tag(ws.workspaceId)
                    }
                }
                Picker("Agent", selection: $kind) {
                    ForEach(kinds, id: \.self) { Text($0).tag($0) }
                }
                TextField("Name", text: $name, prompt: Text(kind.isEmpty ? "Name" : kind))
                    .focused($nameFocused)
                    .onSubmit { if canStart { start() } }
                Toggle("Start on a new worktree", isOn: $onWorktree)
                if onWorktree {
                    TextField("Branch", text: $branch, prompt: Text(suggestedBranch))
                }
            }
            .formStyle(.columns)

            if onWorktree {
                Text("Creates the branch from the workspace's repo, checks it out in its own folder, and opens it as a new workspace.")
                    .font(.system(size: 12)).foregroundStyle(Theme.text3)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if store.workspaces.isEmpty {
                Text("Create a workspace first. Agents run inside one.")
                    .font(.system(size: 12)).foregroundStyle(Theme.text3)
            }
            if let error {
                Text(error).font(.system(size: 12)).foregroundStyle(Theme.danger)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack {
                if starting { ProgressView().controlSize(.small) }
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Start") { start() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canStart)
            }
        }
        .padding(20)
        .frame(width: 380)
        .onAppear {
            workspaceId = initialWorkspace?.workspaceId ?? store.workspaces.first?.workspaceId ?? ""
            kind = kinds.contains("claude") ? "claude" : kinds.first ?? ""
            // Ready to type a name (or just press Return) the moment it appears.
            nameFocused = true
        }
    }

    /// Branch name from the agent name: lowercase, spaces to dashes.
    private var suggestedBranch: String {
        let base = name.trimmingCharacters(in: .whitespaces).isEmpty ? kind : name
        return base.lowercased().split(whereSeparator: { !$0.isLetter && !$0.isNumber }).joined(separator: "-")
    }

    private func start() {
        guard let ws = store.workspace(id: workspaceId) else { return }
        starting = true
        error = nil
        let worktreeBranch = onWorktree ? (branch.trimmingCharacters(in: .whitespaces).isEmpty ? suggestedBranch : branch) : nil
        Task {
            let ok = await store.startAgent(kind: kind, name: name, in: ws, worktreeBranch: worktreeBranch)
            starting = false
            if ok {
                dismiss()
            } else {
                // The sheet shows the reason, so don't repeat it in the sidebar banner.
                error = store.actionError
                store.actionError = nil
            }
        }
    }
}

/// Worktrees of a workspace's repo. Opens the ones that aren't open yet.
private struct WorktreeSheet: View {
    @Environment(HerdrStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let workspace: Workspace

    @State private var worktrees: [Worktree]?
    @State private var error: String?
    @State private var opening: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Worktrees of \(store.title(of: workspace))").font(.system(size: 15, weight: .semibold))

            if let error {
                Text(error).font(.system(size: 12)).foregroundStyle(Theme.danger)
                    .fixedSize(horizontal: false, vertical: true)
            } else if let worktrees {
                ScrollView {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(worktrees) { wt in row(wt) }
                    }
                }
                .frame(maxHeight: 280)
            } else {
                ProgressView().controlSize(.small)
            }

            Text("To make a new one, use New Agent… and turn on Start on a new worktree.")
                .font(.system(size: 12)).foregroundStyle(Theme.text3)

            HStack {
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 460)
        .task { await load() }
    }

    private func row(_ wt: Worktree) -> some View {
        HStack(spacing: 10) {
            PhIcon(wt.isLinkedWorktree == true ? .branch : .folder, size: 13)
                .foregroundStyle(Theme.text2)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 2) {
                Text(wt.branch ?? (wt.isDetached == true ? "detached" : "no branch"))
                    .font(.system(size: 13, weight: .medium))
                Text(wt.path).font(.system(size: 11.5)).foregroundStyle(Theme.text3)
                    .lineLimit(1).truncationMode(.middle)
            }
            Spacer(minLength: 8)
            if wt.openWorkspaceId != nil {
                Text("Open").font(.system(size: 12)).foregroundStyle(Theme.text3)
            } else if opening == wt.path {
                ProgressView().controlSize(.small)
            } else {
                Button("Open") { open(wt) }
            }
        }
        .padding(.vertical, 6)
    }

    private func load() async {
        worktrees = await store.worktrees(of: workspace)
        if worktrees == nil {
            error = store.actionError
            store.actionError = nil
        }
    }

    private func open(_ wt: Worktree) {
        opening = wt.path
        Task {
            if await store.openWorktree(wt, from: workspace) {
                await load()
            } else {
                error = store.actionError
                store.actionError = nil
            }
            opening = nil
        }
    }
}

/// Last failed action. Stays until dismissed or the next action runs.
private struct ErrorBanner: View {
    let text: String
    let dismiss: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            PhIcon(.warning, size: 12, weight: .fill)
                .foregroundStyle(Theme.danger)
            Text(text)
                .font(.system(size: 12.5))
                .foregroundStyle(Theme.text)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
            Spacer(minLength: 4)
            Button(action: dismiss) {
                PhIcon(.x, size: 10).foregroundStyle(Theme.text3)
            }
            .buttonStyle(.plain)
            .pointerCursor()
            .accessibilityLabel("Dismiss error")
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 8).fill(Theme.danger.opacity(0.12)))
        .padding(.horizontal, Theme.space)
        .padding(.bottom, Theme.space)
    }
}

private struct ActionRow: View {
    let icon: Icon
    let title: String
    var badge = 0
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: Theme.space) {
                PhIcon(icon, size: 13.5)
                    .rowForeground(Theme.text3)
                    .frame(width: Sidebar.iconBox)
                Text(title)
                    .font(.system(size: 13))
                    .rowForeground()
                Spacer()
                if badge > 0 { CountBadge(count: badge) }
            }
            .padding(.horizontal, Theme.space)
            .frame(height: Sidebar.rowHeight)
            .contentShape(Rectangle())
        }
        .buttonStyle(RowButtonStyle())
    }
}

private struct WorkspaceRow: View {
    @Environment(HerdrStore.self) private var store
    let workspace: Workspace
    let open: Bool
    let toggle: () -> Void
    let newAgent: () -> Void
    @State private var hovered = false

    var body: some View {
        Button(action: toggle) {
            HStack(spacing: Theme.space) {
                PhIcon(open ? .folderOpen : .folder, size: 13.5, weight: .fill)
                    .rowTinted(Theme.workspaceTint(workspace.workspaceId, scope: store.workspaceScope))
                    .frame(width: Sidebar.iconBox)
                Text(store.title(of: workspace))
                    .font(.system(size: 13))
                    .rowForeground()
                    .lineLimit(1)
                Spacer(minLength: 4)
                Group {
                    if open {
                        Text("\(store.panes(in: workspace).count)")
                            .font(.system(size: 11.5).monospacedDigit())
                            .foregroundStyle(Theme.text4)
                    } else {
                        StatusGlyph(status: workspace.agentStatus, isAgent: false)
                    }
                }
                .frame(minWidth: 12, alignment: .trailing)
                .opacity(hovered ? 0 : 1)
            }
            .padding(.leading, Theme.space)
            .padding(.trailing, Sidebar.trailingColumn - 6)
            .frame(height: Sidebar.rowHeight)
            .contentShape(Rectangle())
        }
        .buttonStyle(RowButtonStyle(lit: hovered))
        // On hover the count gives way to a + that starts an agent in this workspace.
        .overlay(alignment: .trailing) {
            if hovered {
                IconButton(icon: .plus, help: "New agent in \(store.title(of: workspace))", action: newAgent)
                    .padding(.trailing, Sidebar.trailingColumn - 13)
            }
        }
        .onHover { hovered = $0 }
        .accessibilityHint(open ? "Collapse" : "Expand")
        .accessibilityAction(named: "New agent", newAgent)
    }
}

/// One agent or shell: the "channel" of the sidebar.
struct PaneRow: View {
    @Environment(HerdrStore.self) private var store
    let pane: Pane
    var subtitle: String?
    var indent: CGFloat = Theme.space

    private var selected: Bool { store.selectedPaneId == pane.paneId }

    var body: some View {
        Button { store.selectedPaneId = pane.paneId } label: {
            HStack(spacing: Theme.space) {
                // The agent's logo; a terminal for shells, a sparkle for agents Paca has no logo for.
                Group {
                    if let logo = pane.agent.flatMap({ AgentLogo.image(for: $0, side: 14) }) {
                        Image(nsImage: logo).renderingMode(.template)
                    } else {
                        PhIcon(pane.isAgent ? .sparkle : .terminal, size: 13.5)
                    }
                }
                .rowForeground(Theme.text3)
                .frame(width: Sidebar.iconBox)
                VStack(alignment: .leading, spacing: 2) {
                    Text(pane.displayName)
                        .font(.system(size: 13, weight: pane.agentStatus == .blocked ? .semibold : .regular))
                        .rowForeground()
                        .lineLimit(1)
                    if let subtitle {
                        Text([pane.kind, subtitle].compactMap { $0 }.joined(separator: " · "))
                            .font(.system(size: 12))
                            .foregroundStyle(Theme.text3)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 6)
                if pane.agentLaunchPending {
                    ProgressView().controlSize(.mini).help("Starting…")
                } else if pane.isAgent {
                    StatusGlyph(status: pane.agentStatus)
                }
            }
            .padding(.leading, indent)
            .padding(.trailing, Sidebar.trailingColumn - 6)
            .frame(minHeight: subtitle == nil ? Sidebar.rowHeight : 40)
            .contentShape(Rectangle())
        }
        .buttonStyle(RowButtonStyle(selected: selected))
        .hoverTip(pane.agentStatus == .blocked ? "\(pane.displayName) needs input" : pane.displayName, edge: .trailing)
    }
}
