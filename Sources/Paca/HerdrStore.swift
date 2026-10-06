import Foundation
import HerdrKit
import Observation

/// App-wide view of one herdr server: latest snapshot, kept fresh by events.
@MainActor
@Observable
final class HerdrStore {
    private(set) var snapshot: SessionSnapshot?
    private(set) var connectionError: String?
    /// Last failed action, shown in the sidebar until dismissed or the next action runs.
    var actionError: String?
    /// Agent kinds the server can start, loaded once per connection.
    private(set) var agentKinds: [String] = []
    /// The focused pane. With a split, the other visible pane is `splitOther`.
    var selectedPaneId: String? {
        didSet {
            if let id = selectedPaneId, !openTabs.contains(id) { openTabs.append(id) }
            if let id = selectedPaneId { recentTabs.removeAll { $0 == id }; recentTabs.insert(id, at: 0) }
            // Focusing the other side of a split: swap roles, keep both panes where they are.
            if splitAxis != nil, let id = selectedPaneId, id == splitOther {
                splitOther = oldValue
                focusedSlot = 1 - focusedSlot
            }
        }
    }

    // MARK: Split view

    enum SplitAxis { case horizontal, vertical }

    /// Nil when not split. Horizontal puts panes side by side.
    private(set) var splitAxis: SplitAxis?
    /// The visible pane that isn't focused. Nil shows a picker in that slot.
    private(set) var splitOther: String?
    /// Which slot (0 = left/top, 1 = right/bottom) holds `selectedPaneId`.
    private(set) var focusedSlot = 0
    /// Most recently focused first; the split opens with the previous one.
    private var recentTabs: [String] = []

    /// Pane ids per slot, left/top first. One entry when not split; nil is an empty slot.
    var slots: [String?] {
        let focused = pane(id: selectedPaneId)?.paneId
        guard splitAxis != nil else { return [focused] }
        let other = pane(id: splitOther)?.paneId
        return focusedSlot == 0 ? [focused, other] : [other, focused]
    }

    /// ⌘D / ⌘⇧D: split along `axis`, or close the split when it's already that way.
    /// The new side shows the previously used tab and takes focus.
    func toggleSplit(_ axis: SplitAxis) {
        if splitAxis == axis { closeSplit(); return }
        if splitAxis != nil { splitAxis = axis; return }
        guard let current = selectedPaneId else { return }
        splitAxis = axis
        let candidate = recentTabs.first { $0 != current && pane(id: $0) != nil && openTabs.contains($0) }
        splitOther = current
        focusedSlot = 1
        if let candidate {
            selectedPaneId = candidate
        } else {
            // Nothing else open: the new side starts as a picker; focus stays on the existing pane.
            selectedPaneId = nil
            splitOther = current
        }
    }

    /// Puts `paneId` in the split's empty or unfocused slot and focuses it.
    func showInSplit(_ paneId: String) {
        guard splitAxis != nil else { selectedPaneId = paneId; return }
        if selectedPaneId == nil { selectedPaneId = paneId; return }
        splitOther = selectedPaneId
        focusedSlot = 1 - focusedSlot
        selectedPaneId = paneId
    }

    /// Takes `id` out of the split; the other side fills the area. The tab stays open.
    func removeFromSplit(_ id: String) {
        guard splitAxis != nil else { return }
        let survivor = id == selectedPaneId ? splitOther : selectedPaneId
        splitAxis = nil
        splitOther = nil
        focusedSlot = 0
        selectedPaneId = survivor
    }

    func closeSplit() {
        if selectedPaneId == nil { selectedPaneId = splitOther }
        splitAxis = nil
        splitOther = nil
        focusedSlot = 0
    }
    var sidebarMode: SidebarMode = .home
    /// Panes open as tabs in the top bar, in the order they were opened.
    private(set) var openTabs: [String] = []
    /// Set to present the New agent sheet from anywhere (sidebar row, "+" tab).
    var newAgentRequest: NewAgentRequest?

    struct NewAgentRequest: Identifiable {
        let id = UUID()
        let workspace: Workspace?
    }

    /// Tabs whose panes still exist.
    var tabs: [Pane] { openTabs.compactMap { pane(id: $0) } }

    /// Closes the tab only; the pane keeps running in herdr. Selection moves to a neighbor.
    func closeTab(_ id: String) {
        guard let index = openTabs.firstIndex(of: id) else { return }
        openTabs.remove(at: index)
        recentTabs.removeAll { $0 == id }
        // Closing one side of a split leaves the other side on its own.
        if splitAxis != nil, id == splitOther || id == selectedPaneId {
            let survivor = id == splitOther ? selectedPaneId : splitOther
            splitAxis = nil
            splitOther = nil
            focusedSlot = 0
            selectedPaneId = survivor
            return
        }
        if selectedPaneId == id {
            let live = openTabs.filter { pane(id: $0) != nil }
            selectedPaneId = live.isEmpty ? nil : live[min(index, live.count - 1)]
        }
    }

    enum SidebarMode { case home, inbox, activity }

    /// The herdr session Paca is showing. "default" is herdr's unnamed session.
    private(set) var sessionName: String
    private(set) var socketPath: String
    /// Every session herdr knows about, running or not. Refreshed on connect and after session actions.
    private(set) var sessions: [HerdrSession] = []
    /// Saved SSH machines (herdr's own list). `machine` is set while Paca shows one of them.
    private(set) var machines: [HerdrMachine] = []
    private(set) var machine: HerdrMachine?
    @ObservationIgnored private var tunnel: SSHTunnel?
    @ObservationIgnored private var client: HerdrClient?
    /// The live connection, for commands outside the main event loop.
    var currentClient: HerdrClient? { client }
    /// Called with agents that just became blocked or done. Set by the notifier.
    @ObservationIgnored var onAttention: (([Pane]) -> Void)?
    /// Called with every agent status change. Set by the orchestrator (activity log and rules).
    @ObservationIgnored var onStatusChanges: (([StatusChange]) -> Void)?
    @ObservationIgnored private var loop: Task<Void, Never>?

    static let lastSessionKey = "paca.lastSession"
    static let lastMachineKey = "paca.lastMachine"
    /// False for scripted launches (`--session`, `--machine`, `--snapshot`): they must not
    /// change which target the next normal launch opens.
    @ObservationIgnored var remembersTarget = true
    /// `--machine LABEL` at launch: open this saved machine instead of the remembered target.
    @ObservationIgnored var launchMachine: String?
    /// True when `--session` was passed, so a remembered machine doesn't override it.
    @ObservationIgnored var launchSessionGiven = false

    /// What the rail and notifications call the current target: the machine, or the session.
    var targetName: String { machine?.label ?? sessionName }
    var isRemote: Bool { machine != nil }
    /// Keys per-workspace settings (folder colors) to this machine and session.
    var workspaceScope: String { "\(machine?.id ?? "local")/\(sessionName)" }

    init(session: String = "default") {
        sessionName = session
        socketPath = HerdrClient.defaultSocketPath(session: session)
    }

    var workspaces: [Workspace] { snapshot?.workspaces ?? [] }
    var panes: [Pane] { snapshot?.panes ?? [] }

    func panes(in workspace: Workspace) -> [Pane] {
        snapshot?.panes(in: workspace) ?? []
    }

    var needsYou: [Pane] { panes.filter { $0.agentStatus.needsAttention } }

    func count(_ status: AgentStatus) -> Int {
        panes.filter { $0.agentStatus == status }.count
    }

    func pane(id: String?) -> Pane? {
        guard let id else { return nil }
        return panes.first { $0.paneId == id }
    }

    /// Workspace label, with herdr's number appended when two workspaces share a label.
    func title(of workspace: Workspace) -> String {
        let twins = workspaces.filter { $0.label == workspace.label }
        return twins.count > 1 ? "\(workspace.label) \(workspace.number)" : workspace.label
    }

    func workspaceTitle(id: String) -> String? {
        workspace(id: id).map(title(of:))
    }

    func workspace(id: String) -> Workspace? {
        workspaces.first { $0.workspaceId == id }
    }

    func start() {
        guard loop == nil else { return }
        loop = Task {
            await refreshSessions()
            await refreshMachines()
            // An explicit `--session` beats the remembered machine.
            let remembered = launchSessionGiven ? nil : UserDefaults.standard.string(forKey: Self.lastMachineKey)
            let wanted = launchMachine ?? remembered
            if let wanted, let saved = machines.first(where: { ($0.id == wanted || $0.label == wanted) && $0.enabled }) {
                let keep = selectedPaneId // `--select` from launch
                connect(to: saved)
                selectedPaneId = keep
                return
            }
            // A remembered session that has since stopped falls back to the default one.
            // Never for an explicit `--session`: scripted runs must not land in the real session.
            if !launchSessionGiven, sessionName != "default", sessions.contains(where: { $0.name == sessionName && !$0.running }) {
                connect(to: "default")
                return
            }
            await run(tunnel: nil)
        }
    }

    // MARK: Actions

    // Every mutation goes through here. Nothing is applied optimistically: each action
    // waits for herdr's reply, then resnapshots. Events from other clients refresh too.

    func createWorkspace(at folder: URL) async {
        await createWorkspace(atPath: folder.path)
    }

    /// Path on the herdr machine, so remote workspaces can be typed instead of picked.
    func createWorkspace(atPath path: String) async {
        let path = path.trimmingCharacters(in: .whitespaces)
        guard !path.isEmpty else { return }
        let label = (path as NSString).lastPathComponent
        await perform("Couldn't create the workspace") {
            try await $0.createWorkspace(cwd: path, label: label.isEmpty || label == "/" ? nil : label)
        }
    }

    func renameWorkspace(_ workspace: Workspace, to label: String) async {
        let label = label.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !label.isEmpty, label != workspace.label else { return }
        await perform("Couldn't rename \(workspace.label)") {
            try await $0.renameWorkspace(workspace.workspaceId, label: label)
        }
    }

    func closeWorkspace(_ workspace: Workspace) async {
        let closed = await perform("Couldn't close \(workspace.label)") {
            try await $0.closeWorkspace(workspace.workspaceId)
        }
        // herdr can hand the id to a later workspace, which shouldn't inherit the color.
        if closed { WorkspaceColors.shared.set(nil, for: workspace.workspaceId, scope: workspaceScope) }
    }

    func moveWorkspace(_ workspaceId: String, to index: Int) async {
        guard workspaces.firstIndex(where: { $0.workspaceId == workspaceId }) != index else { return }
        await perform("Couldn't reorder workspaces") {
            try await $0.moveWorkspace(workspaceId, to: index)
        }
    }

    /// Opens a new tab with a shell in the workspace and selects it.
    func newShell(in workspace: Workspace) async {
        await perform("Couldn't open a shell in \(workspace.label)") { client in
            let pane = try await client.newTab(in: workspace.workspaceId)
            self.selectedPaneId = pane.paneId
        }
    }

    func split(_ pane: Pane, _ direction: HerdrClient.SplitDirection) async {
        await perform("Couldn't split \(pane.displayName)") { client in
            let created = try await client.splitPane(pane.paneId, direction: direction)
            self.selectedPaneId = created.paneId
        }
    }

    /// Starts the agent in a new tab of the workspace, or, with `worktreeBranch`, in a new
    /// worktree of the workspace's repo. If the agent can't start in a new tab, the tab is
    /// closed again. A new worktree is kept, since it may already hold the branch you wanted.
    /// Returns false on failure, with the reason in `actionError`.
    @discardableResult
    func startAgent(kind: String, name: String, in workspace: Workspace, worktreeBranch: String? = nil) async -> Bool {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let branch = worktreeBranch?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return await perform("Couldn't start \(kind)") { client in
            if branch.isEmpty {
                let pane = try await client.newTab(in: workspace.workspaceId)
                do {
                    try await client.startAgent(kind: kind, name: name.isEmpty ? kind : name, in: pane.paneId)
                } catch {
                    try? await client.closePane(pane.paneId)
                    throw error
                }
                self.selectedPaneId = pane.paneId
            } else {
                let created = try await client.createWorktree(from: workspace.workspaceId, branch: branch, base: nil)
                self.selectedPaneId = created.rootPane.paneId
                try await client.startAgent(kind: kind, name: name.isEmpty ? kind : name, in: created.rootPane.paneId)
            }
        }
    }

    // MARK: Worktrees

    /// Worktrees of the workspace's repo, or nil with the reason in `actionError`.
    func worktrees(of workspace: Workspace) async -> [Worktree]? {
        var result: [Worktree]?
        await perform("Couldn't list worktrees for \(workspace.label)") {
            result = try await $0.worktrees(of: workspace.workspaceId)
        }
        return result
    }

    @discardableResult
    func openWorktree(_ worktree: Worktree, from workspace: Workspace) async -> Bool {
        await perform("Couldn't open \(worktree.branch ?? worktree.path)") {
            _ = try await $0.openWorktree(from: workspace.workspaceId, path: worktree.path)
        }
    }

    enum RemoveOutcome { case removed, dirty, failed }

    /// Removes a linked worktree and its workspace. Reports `.dirty` instead of failing when
    /// herdr wants `force` because of uncommitted changes, so the caller can ask again.
    func removeWorktree(_ workspace: Workspace, force: Bool) async -> RemoveOutcome {
        var dirty = false
        let ok = await perform("Couldn't remove \(workspace.label)") { client in
            do {
                try await client.removeWorktree(workspace.workspaceId, force: force)
            } catch HerdrError.server(code: "dirty_worktree_requires_force", _) where !force {
                dirty = true
            }
        }
        return dirty ? .dirty : ok ? .removed : .failed
    }

    /// Up to `limit` uncommitted paths in the workspace's checkout, from `git status`.
    /// Empty when git isn't available or the checkout isn't on this Mac.
    func uncommittedFiles(in workspace: Workspace, limit: Int = 6) -> [String] {
        guard !isRemote, let path = workspace.worktree?.checkoutPath else { return [] }
        let git = Process()
        git.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        git.arguments = ["-C", path, "status", "--porcelain"]
        let out = Pipe()
        git.standardOutput = out
        git.standardError = Pipe()
        guard (try? git.run()) != nil else { return [] }
        git.waitUntilExit()
        let text = String(decoding: out.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        return text.split(separator: "\n").prefix(limit).map { String($0.dropFirst(3)) }
    }

    /// Agents are renamed through herdr's agent name, shells through the pane label.
    func rename(_ pane: Pane, to name: String) async {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, name != pane.displayName else { return }
        await perform("Couldn't rename \(pane.displayName)") { client in
            if pane.isAgent {
                try await client.renameAgent(in: pane.paneId, to: name)
            } else {
                try await client.renamePane(pane.paneId, label: name)
            }
        }
    }

    func close(_ pane: Pane) async {
        await perform("Couldn't close \(pane.displayName)") {
            try await $0.closePane(pane.paneId)
        }
    }

    func showInHerdr(_ pane: Pane) async {
        await perform("Couldn't show \(pane.displayName) in herdr") {
            try await $0.focusPane(pane.paneId, isAgent: pane.isAgent)
        }
    }

    /// Sends text to an agent, for rules. Throws herdr's error instead of showing the banner,
    /// so the activity log can record it.
    func prompt(_ pane: Pane, text: String) async throws {
        guard let client else { throw HerdrError.disconnected }
        try await client.prompt(agent: pane.paneId, text: text)
    }

    func recentOutput(of paneId: String, lines: Int) async throws -> String {
        guard let client else { throw HerdrError.disconnected }
        return try await client.recentOutput(of: paneId, lines: lines)
    }

    /// The agent named `name` (case-insensitive) on the current session or machine.
    func agent(named name: String) -> Pane? {
        panes.first { $0.isAgent && $0.displayName.compare(name, options: .caseInsensitive) == .orderedSame }
    }

    /// Agent panes in the workspace that are mid-task. Closing them loses work.
    func busyAgents(in workspace: Workspace) -> [Pane] {
        panes(in: workspace).filter { $0.isAgent && ($0.agentStatus == .working || $0.agentStatus == .blocked) }
    }

    @discardableResult
    private func perform(_ failure: String, _ work: (HerdrClient) async throws -> Void) async -> Bool {
        actionError = nil
        guard let client else {
            actionError = "\(failure): Paca isn't connected to herdr."
            return false
        }
        do {
            try await work(client)
            try await refresh()
            return true
        } catch {
            let message = (error as? HerdrError)?.userMessage ?? "\(error)"
            actionError = "\(failure): \(message)"
            debugLog("action failed: \(failure): \(error)")
            return false
        }
    }

    // MARK: Sessions

    func refreshSessions() async {
        if let list = try? await HerdrSessions.list() { sessions = list }
    }

    /// Points the store at another session's socket and starts over from its snapshot.
    func switchSession(to name: String) {
        guard name != sessionName || machine != nil else { return }
        connect(to: name)
    }

    // MARK: Machines

    func refreshMachines() async {
        if let list = try? await HerdrMachines.list() { machines = list }
    }

    func switchMachine(to machine: HerdrMachine) {
        guard machine.id != self.machine?.id else { return }
        connect(to: machine)
    }

    /// Drops the tunnel and opens a fresh one, for when the network changed under it.
    func reconnect() {
        if let machine { connect(to: machine) } else { connect(to: sessionName) }
    }

    /// Saves a machine with herdr (which installs herdr there if needed) and switches to it.
    @discardableResult
    func addMachine(target: String, label: String) async -> Bool {
        let target = target.trimmingCharacters(in: .whitespaces)
        let label = label.trimmingCharacters(in: .whitespaces).isEmpty ? target : label.trimmingCharacters(in: .whitespaces)
        let ok = await performSession("Couldn't add \(target)") {
            try await HerdrMachines.add(target: target, label: label)
        }
        await refreshMachines()
        if ok, let saved = machines.first(where: { $0.target == target && $0.label == label }) {
            connect(to: saved)
        }
        return ok
    }

    /// Forgets the machine in herdr. Its remote server and agents keep running.
    func removeMachine(_ machine: HerdrMachine) async {
        let wasCurrent = machine.id == self.machine?.id
        await performSession("Couldn't remove \(machine.label)") { try await HerdrMachines.remove(machine) }
        await refreshMachines()
        if wasCurrent { connect(to: "default") }
    }

    func newSession(named name: String) async {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        if await performSession("Couldn't create session \(name)", { try await HerdrSessions.start(name) }) {
            connect(to: name)
        }
    }

    func startSession(_ session: HerdrSession) async {
        if await performSession("Couldn't start \(session.name)", { try await HerdrSessions.start(session.name) }) {
            connect(to: session.name)
        }
    }

    /// Stops a session's server. Stopping the one on screen moves Paca to the default session.
    func stopSession(_ session: HerdrSession) async {
        if await performSession("Couldn't stop \(session.name)", { try await HerdrSessions.stop(session.name) }),
           session.name == sessionName {
            connect(to: "default")
        }
    }

    func deleteSession(_ session: HerdrSession) async {
        await performSession("Couldn't delete \(session.name)") { try await HerdrSessions.delete(session.name) }
    }

    @discardableResult
    private func performSession(_ failure: String, _ work: () async throws -> Void) async -> Bool {
        actionError = nil
        defer { Task { await refreshSessions() } }
        do {
            try await work()
            await refreshSessions()
            return true
        } catch {
            let message = (error as? HerdrError)?.userMessage ?? "\(error)"
            actionError = "\(failure): \(message)"
            debugLog("session action failed: \(failure): \(error)")
            return false
        }
    }

    private func connect(to name: String) {
        reset()
        sessionName = name
        socketPath = HerdrClient.defaultSocketPath(session: name)
        if remembersTarget {
            UserDefaults.standard.set(name, forKey: Self.lastSessionKey)
            UserDefaults.standard.removeObject(forKey: Self.lastMachineKey)
        }
        loop = Task { await run(tunnel: nil) }
    }

    private func connect(to machine: HerdrMachine) {
        reset()
        let tunnel = SSHTunnel(machine: machine)
        self.tunnel = tunnel
        self.machine = machine
        sessionName = machine.session
        socketPath = tunnel.socketPath
        connectionError = "Connecting to \(machine.label)…"
        if remembersTarget { UserDefaults.standard.set(machine.id, forKey: Self.lastMachineKey) }
        loop = Task { await run(tunnel: tunnel) }
    }

    /// Closes the SSH tunnel when Paca quits, so no `ssh` process outlives it.
    func shutDown() {
        loop?.cancel()
        tunnel?.stop()
    }

    private func reset() {
        loop?.cancel()
        loop = nil
        tunnel?.stop()
        tunnel = nil
        machine = nil
        client = nil
        snapshot = nil
        selectedPaneId = nil
        agentKinds = []
        connectionError = nil
    }

    // MARK: Event loop

    /// One loop per session. It keeps its own socket path and client, and drops its results
    /// once cancelled, so a session switch never shows the old session's data.
    private func run(tunnel: SSHTunnel? = nil) async {
        let path = socketPath
        let client = HerdrClient(socketPath: path)
        var startedServer = false
        while !Task.isCancelled {
            do {
                // Remote: (re)open the SSH tunnel first. A no-op while it's healthy.
                try await tunnel?.start()
                try await refresh(client)
                guard !Task.isCancelled else { return }
                self.client = client
                connectionError = nil
                if agentKinds.isEmpty, let kinds = try? await client.agentKinds(), !Task.isCancelled { agentKinds = kinds }

                // Status subscriptions are per pane, so resubscribe whenever the pane set changes.
                let paneIds = Set(panes.map(\.paneId))
                let stream = HerdrClient.events(socketPath: path, subscriptions: subscriptions(for: paneIds))
                for try await _ in stream {
                    try await refresh(client)
                    if Set(panes.map(\.paneId)) != paneIds { break }
                }
            } catch HerdrError.notRunning where tunnel == nil && !startedServer {
                // No local server yet: start one headless, once per connect, then retry.
                startedServer = true
                guard !Task.isCancelled else { return }
                connectionError = "Starting herdr…"
                debugLog("herdr not running, starting session \(sessionName)")
                do {
                    try await HerdrSessions.start(sessionName)
                    await refreshSessions()
                } catch {
                    guard !Task.isCancelled else { return }
                    connectionError = "Couldn't start herdr: \((error as? HerdrError)?.userMessage ?? "\(error)")"
                    debugLog("auto-start failed: \(error)")
                    try? await Task.sleep(for: .seconds(2))
                }
            } catch {
                guard !Task.isCancelled else { return }
                connectionError = "\(error)"
                debugLog("connection error: \(error)")
                self.client = nil
                try? await Task.sleep(for: .seconds(2))
            }
        }
    }

    /// Resnapshots through the live client. Actions call this after each mutation.
    private func refresh() async throws {
        guard let client else { throw HerdrError.disconnected }
        try await refresh(client)
    }

    private func refresh(_ client: HerdrClient) async throws {
        let next = try await client.snapshot()
        guard !Task.isCancelled, client.socketPath == socketPath else { return }
        let changes = next.statusChanges(since: snapshot)
        let changed = next.attentionTransitions(since: snapshot)
        snapshot = next
        if !changes.isEmpty { onStatusChanges?(changes) }
        if !changed.isEmpty { onAttention?(changed) }
        debugLog("snapshot \(panes.count) panes")
        if let id = selectedPaneId, pane(id: id) == nil { selectedPaneId = nil }
    }

    private func subscriptions(for paneIds: Set<String>) -> [[String: Any]] {
        let lifecycle: [[String: Any]] = [
            "workspace.created", "workspace.closed", "workspace.renamed", "workspace.updated",
            "workspace.moved", "workspace.reordered",
            "tab.created", "tab.closed", "tab.renamed",
            "pane.created", "pane.closed", "pane.exited", "pane.agent_detected",
        ].map { ["type": $0] }
        return lifecycle + paneIds.sorted().map { ["type": "pane.agent_status_changed", "pane_id": $0] }
    }
}

// MARK: - Scrollback commands (Ghostty's jump_to_prompt, scroll_to_top/bottom)

extension HerdrStore {
    /// Runs a scrollback command against herdr, which holds the pane's history.
    func perform(_ command: PaneCommand, on paneId: String) async {
        guard let client = currentClient else { return }
        do {
            let scroll = try await Self.scrollInfo(paneId, client)
            let target: Int
            switch command {
            case .scrollToTop: target = scroll.max
            case .scrollToBottom: target = 0
            case .jumpToPrompt(let step):
                guard let offset = try await promptOffset(paneId, step: step, scroll: scroll, client) else { return }
                target = offset
            }
            _ = try await client.call("pane.scroll", params: ["pane_id": paneId, "offset_from_bottom": target])
        } catch {
            debugLog("scrollback command failed: \(error)")
        }
    }

    private struct ScrollInfo { let offset: Int; let max: Int; let viewport: Int }

    private static func scrollInfo(_ paneId: String, _ client: HerdrClient) async throws -> ScrollInfo {
        let data = try await client.call("pane.get", params: ["pane_id": paneId])
        let pane = (try JSONSerialization.jsonObject(with: data) as? [String: Any])?["pane"] as? [String: Any]
        let scroll = pane?["scroll"] as? [String: Any] ?? [:]
        return ScrollInfo(offset: scroll["offset_from_bottom"] as? Int ?? 0,
                          max: scroll["max_offset_from_bottom"] as? Int ?? 0,
                          viewport: scroll["viewport_rows"] as? Int ?? 0)
    }

    /// Ghostty jumps between shell-integration prompt marks; herdr doesn't keep those, so Paca
    /// looks for prompt-shaped rows in the scrollback (shell `❯ $ %`, Claude `>`, Codex `›`)
    /// and puts the previous or next one at the top of the view.
    private func promptOffset(_ paneId: String, step: Int, scroll: ScrollInfo, _ client: HerdrClient) async throws -> Int? {
        let total = scroll.max + scroll.viewport
        let data = try await client.call("pane.read", params: ["pane_id": paneId, "source": "recent", "lines": total])
        let read = (try JSONSerialization.jsonObject(with: data) as? [String: Any])?["read"] as? [String: Any]
        let rows = ((read?["text"] as? String) ?? "").components(separatedBy: "\n").prefix(total)
        let prompts = rows.indices.filter { Self.isPromptRow(rows[$0]) }
        let top = total - scroll.viewport - scroll.offset
        let row = step < 0 ? prompts.last(where: { $0 < top }) : prompts.first(where: { $0 > top })
        guard let row else { return step < 0 ? nil : 0 }
        return min(max(total - scroll.viewport - row, 0), scroll.max)
    }

    static func isPromptRow(_ row: String) -> Bool {
        guard let first = row.first else { return false }
        let rest = row.dropFirst()
        return ["❯", "➜", "$", "%", ">", "›", "λ"].contains(first) && (rest.isEmpty || rest.first == " ")
    }
}
