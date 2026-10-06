import Foundation
import HerdrKit
import PacaTheme

// paca-probe: check that Paca can talk to a running herdr server.
//
//   paca-probe [--session NAME] snapshot   print workspaces and panes with status
//   paca-probe [--session NAME] watch      stream lifecycle + agent status events
//   paca-probe [--session NAME] frame PANE attach to PANE, print the first frame size, release
//   paca-probe --session NAME smoke        run every write action Paca uses, check each in the snapshot

setvbuf(stdout, nil, _IOLBF, 0) // line-buffer so piped output shows up live

var args = Array(CommandLine.arguments.dropFirst())
var session: String?
if let i = args.firstIndex(of: "--session"), i + 1 < args.count {
    session = args[i + 1]
    args.removeSubrange(i...(i + 1))
}
let command = args.first ?? "snapshot"
let socketPath = HerdrClient.defaultSocketPath(session: session)

let glyph: [AgentStatus: String] = [.working: "◐", .blocked: "⚑", .done: "✓", .idle: "○", .unknown: "·"]

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("paca-probe: \(message)\n".utf8))
    exit(1)
}

func printSnapshot(_ snap: SessionSnapshot) {
    print("herdr \(snap.version) · protocol \(snap.protocolVersion) · \(socketPath)")
    for ws in snap.workspaces {
        print("\(glyph[ws.agentStatus]!) \(ws.label) [\(ws.workspaceId)]")
        for pane in snap.panes(in: ws) {
            let agent = pane.agent.map { " (\($0))" } ?? ""
            print("    \(glyph[pane.agentStatus]!) \(pane.paneId)  \(pane.displayName)\(agent)")
        }
    }
}

func watch(_ client: HerdrClient) async throws {
    let snap = try await client.snapshot()
    printSnapshot(snap)
    print("--- watching (ctrl+c to stop)")

    var subs: [[String: Any]] = [
        "workspace.created", "workspace.closed", "workspace.renamed",
        "pane.created", "pane.closed", "pane.agent_detected",
    ].map { ["type": $0] }
    // herdr scopes status subscriptions to a pane, so subscribe per live pane.
    subs += snap.panes.map { ["type": "pane.agent_status_changed", "pane_id": $0.paneId] }

    for try await event in HerdrClient.events(socketPath: socketPath, subscriptions: subs) {
        if event.kind == "pane_agent_status_changed", let change = try? event.decode(PaneStatusChange.self) {
            print("\(glyph[change.agentStatus]!) \(change.paneId) → \(change.agentStatus.rawValue)")
        } else {
            print("• \(event.kind)")
        }
    }
    print("--- stream closed")
}

func frame(_ paneId: String) async {
    let term = TerminalSession(paneId: paneId, socketPath: socketPath, cols: 80, rows: 24)
    let timeout = Task {
        try await Task.sleep(for: .seconds(10))
        fail("no frame within 10s")
    }
    await withCheckedContinuation { (done: CheckedContinuation<Void, Never>) in
        term.onFrame = { f in
            print("frame \(f.cols)x\(f.rows) full=\(f.full) bytes=\(f.bytes.count)")
            term.onFrame = nil
            term.release()
        }
        term.onClosed = { reason in
            print("closed\(reason.map { ": \($0)" } ?? "")")
            done.resume()
        }
        do { try term.start() } catch { fail("could not start herdr: \(error)") }
    }
    timeout.cancel()
}

/// Exercises each write action through `HerdrClient` and checks the result in a fresh snapshot.
/// Everything it creates is closed again. Refuses the default session.
func smoke(_ client: HerdrClient, session: String?) async throws {
    guard let session, session != "default" else { fail("smoke needs --session NAME (never the default session)") }
    struct StepFailed: Error {}
    var step = 0
    func check(_ name: String, _ ok: Bool) throws {
        step += 1
        print("\(ok ? "ok  " : "FAIL") \(step). \(name)")
        if !ok { throw StepFailed() }
    }
    let label = "paca-smoke-\(Int(Date().timeIntervalSince1970))"

    // Workspaces
    let ws = try await client.createWorkspace(cwd: NSTemporaryDirectory(), label: label)
    do {
        try await smokeSteps(client, ws: ws, label: label, check: check)
    } catch {
        // Leave the session as we found it, whatever failed.
        try? await client.closeWorkspace(ws.workspaceId)
        if !(error is StepFailed) { print("FAIL \(step + 1). \(error)") }
        exit(1)
    }
    print("smoke passed on session \(session)")
}

func smokeSteps(_ client: HerdrClient, ws: Workspace, label: String, check: (String, Bool) throws -> Void) async throws {
    var snap = try await client.snapshot()
    try check("workspace.create", snap.workspaces.contains { $0.workspaceId == ws.workspaceId && $0.label == label })

    try await client.renameWorkspace(ws.workspaceId, label: label + "-renamed")
    snap = try await client.snapshot()
    try check("workspace.rename", snap.workspaces.first { $0.workspaceId == ws.workspaceId }?.label == label + "-renamed")

    try await client.moveWorkspace(ws.workspaceId, to: 0)
    snap = try await client.snapshot()
    try check("workspace.move to 0", snap.workspaces.first?.workspaceId == ws.workspaceId)

    // Panes and agents, inside the smoke workspace
    let kinds = try await client.agentKinds()
    try check("server.agent_manifests (\(kinds.count) kinds)", !kinds.isEmpty)

    let tabPane = try await client.newTab(in: ws.workspaceId)
    snap = try await client.snapshot()
    try check("tab.create", snap.panes.contains { $0.paneId == tabPane.paneId && $0.workspaceId == ws.workspaceId })

    let split = try await client.splitPane(tabPane.paneId, direction: .down)
    snap = try await client.snapshot()
    try check("pane.split", snap.panes.contains { $0.paneId == split.paneId && $0.tabId == tabPane.tabId })

    try await client.renamePane(split.paneId, label: "smoke shell")
    snap = try await client.snapshot()
    try check("pane.rename", snap.panes.first { $0.paneId == split.paneId }?.displayName == "smoke shell")

    try await client.focusPane(split.paneId, isAgent: false)
    try check("pane.focus", true)

    try await client.closePane(split.paneId)
    snap = try await client.snapshot()
    try check("pane.close", !snap.panes.contains { $0.paneId == split.paneId })

    // Starts a real agent CLI (no prompt is sent). PACA_SMOKE_AGENT="" skips it.
    let agentKind = ProcessInfo.processInfo.environment["PACA_SMOKE_AGENT"] ?? "claude"
    if agentKind.isEmpty {
        print("skip agent.start (PACA_SMOKE_AGENT is empty)")
    } else {
        try await client.startAgent(kind: agentKind, name: "smoke-agent", in: tabPane.paneId)
        var named = false
        for _ in 0..<30 where !named {
            snap = try await client.snapshot()
            let agent = snap.panes.first { $0.paneId == tabPane.paneId }
            named = agent?.agentName == "smoke-agent" && agent?.agentLaunchPending == false
            if !named { try await Task.sleep(for: .milliseconds(500)) }
        }
        try check("agent.start \(agentKind): named and ready", named)

        try await client.renameAgent(in: tabPane.paneId, to: "smoke-agent-2")
        snap = try await client.snapshot()
        try check("agent.rename", snap.panes.first { $0.paneId == tabPane.paneId }?.displayName == "smoke-agent-2")

        try await client.focusPane(tabPane.paneId, isAgent: true)
        try check("agent.focus", true)
    }

    try await smokeWorktrees(client, check: check)
    try await smokeSessions(check: check)
    try await smokeMachine(check: check)

    try await client.closeWorkspace(ws.workspaceId)
    snap = try await client.snapshot()
    try check("workspace.close", !snap.workspaces.contains { $0.workspaceId == ws.workspaceId })

    do {
        try await client.closeWorkspace(ws.workspaceId)
        try check("closing a missing workspace fails", false)
    } catch let error as HerdrError {
        try check("closing a missing workspace fails (\(error.userMessage))", true)
    }

}

/// Remote machine over an SSH tunnel, only when PACA_SMOKE_MACHINE names a saved machine
/// (label or target). Creates and closes one workspace on it.
func smokeMachine(check: (String, Bool) throws -> Void) async throws {
    guard let wanted = ProcessInfo.processInfo.environment["PACA_SMOKE_MACHINE"], !wanted.isEmpty else {
        print("skip remote machine (set PACA_SMOKE_MACHINE=<label> to test one)")
        return
    }
    let machines = try await HerdrMachines.list()
    guard let machine = machines.first(where: { $0.label == wanted || $0.target == wanted }) else {
        try check("machine \(wanted) is saved in herdr", false)
        return
    }
    let tunnel = SSHTunnel(machine: machine)
    defer { tunnel.stop() }
    try await tunnel.start()
    try check("ssh tunnel to \(machine.label)", tunnel.isRunning)

    let remote = HerdrClient(socketPath: tunnel.socketPath)
    let ws = try await remote.createWorkspace(cwd: "/tmp", label: "paca-smoke-remote")
    var snap = try await remote.snapshot()
    try check("remote workspace.create", snap.workspaces.contains { $0.workspaceId == ws.workspaceId })
    try await remote.closeWorkspace(ws.workspaceId)
    snap = try await remote.snapshot()
    try check("remote workspace.close", !snap.workspaces.contains { $0.workspaceId == ws.workspaceId })

    let clientSocket = (tunnel.socketPath as NSString).deletingLastPathComponent + "/herdr-client.sock"
    try check("terminal socket forwarded", FileManager.default.fileExists(atPath: clientSocket))
}

/// Session lifecycle through the herdr CLI on a scratch session that is deleted again.
func smokeSessions(check: (String, Bool) throws -> Void) async throws {
    let name = "paca-smoke-\(UUID().uuidString.prefix(6).lowercased())"
    func listed() async throws -> HerdrSession? { try await HerdrSessions.list().first { $0.name == name } }
    do {
        try await HerdrSessions.start(name)
        try check("session start \(name)", try await listed()?.running == true)

        do {
            try await HerdrSessions.delete(name)
            try check("deleting a running session fails", false)
        } catch let error as HerdrError {
            try check("deleting a running session fails (\(error.userMessage))", true)
        }

        try await HerdrSessions.stop(name)
        try check("session stop", try await listed()?.running == false)

        try await HerdrSessions.delete(name)
        try check("session delete", try await listed() == nil)

        do {
            try await HerdrSessions.start("bad name!")
            try check("invalid session name is refused", false)
        } catch let error as HerdrError {
            try check("invalid session name is refused (\(error.userMessage))", true)
        }
    } catch {
        try? await HerdrSessions.stop(name)
        try? await HerdrSessions.delete(name)
        throw error
    }
}

@discardableResult
func git(_ args: String...) -> Bool {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: "/usr/bin/git")
    p.arguments = args
    p.standardOutput = FileHandle.nullDevice
    p.standardError = FileHandle.nullDevice
    guard (try? p.run()) != nil else { return false }
    p.waitUntilExit()
    return p.terminationStatus == 0
}

/// Worktree actions against a throwaway git repo. Removes the repo, the workspaces and
/// the worktree checkouts again, also when a step fails.
func smokeWorktrees(_ client: HerdrClient, check: (String, Bool) throws -> Void) async throws {
    let fm = FileManager.default
    let id = UUID().uuidString.prefix(8).lowercased()
    let root = fm.temporaryDirectory.appendingPathComponent("paca-smoke-\(id)")
    // herdr files worktrees under ~/.herdr/worktrees/<repo folder>/<branch>, so the repo
    // folder name must be unique per run or a leftover checkout blocks the next one.
    let repo = root.appendingPathComponent("paca-smoke-repo-\(id)").path
    let manual = root.appendingPathComponent("manual-wt").path
    try fm.createDirectory(atPath: repo, withIntermediateDirectories: true)
    try check("git repo for worktrees", git("-C", repo, "init", "-q") && git("-C", repo, "commit", "-q", "--allow-empty", "-m", "init"))

    let sourceLabel = "paca-smoke-repo-\(id)"
    let source = try await client.createWorkspace(cwd: repo, label: sourceLabel)
    var opened: [String] = [source.workspaceId]
    defer { try? fm.removeItem(atPath: root.path) }
    do {
        let created = try await client.createWorktree(from: source.workspaceId, branch: "smoke-wt", base: nil)
        opened.append(created.workspace.workspaceId)
        var snap = try await client.snapshot()
        try check("worktree.create", snap.workspaces.first { $0.workspaceId == created.workspace.workspaceId }?.isLinkedWorktree == true)
        try check("worktree.create opens one workspace", snap.workspaces.filter { $0.worktree?.repoName == "paca-smoke-repo-\(id)" && $0.isLinkedWorktree == false }.count <= 1)

        let list = try await client.worktrees(of: source.workspaceId)
        try check("worktree.list", list.contains { $0.branch == "smoke-wt" && $0.openWorkspaceId == created.workspace.workspaceId })

        let checkout = created.workspace.worktree?.checkoutPath ?? ""
        fm.createFile(atPath: checkout + "/dirty.txt", contents: Data("x".utf8))
        do {
            try await client.removeWorktree(created.workspace.workspaceId, force: false)
            try check("worktree.remove refuses a dirty checkout", false)
        } catch HerdrError.server(code: "dirty_worktree_requires_force", _) {
            try check("worktree.remove refuses a dirty checkout", true)
        }
        try await client.removeWorktree(created.workspace.workspaceId, force: true)
        snap = try await client.snapshot()
        try check("worktree.remove force", !snap.workspaces.contains { $0.workspaceId == created.workspace.workspaceId } && !fm.fileExists(atPath: checkout))
        opened.removeAll { $0 == created.workspace.workspaceId }

        try check("git worktree add", git("-C", repo, "worktree", "add", "-q", manual, "-b", "manual-wt"))
        let reopened = try await client.openWorktree(from: source.workspaceId, path: manual)
        opened.append(reopened.workspaceId)
        snap = try await client.snapshot()
        try check("worktree.open", snap.workspaces.contains { $0.workspaceId == reopened.workspaceId })
    } catch {
        await cleanUp(client, workspaces: opened, herdrFolder: "paca-smoke-repo-\(id)")
        throw error
    }
    await cleanUp(client, workspaces: opened, herdrFolder: "paca-smoke-repo-\(id)")
}

/// Removes linked worktrees (which deletes their checkouts), closes the rest, and drops
/// herdr's per-repo folder. Prints anything that fails instead of hiding it.
func cleanUp(_ client: HerdrClient, workspaces ids: [String], herdrFolder: String) async {
    let snap = try? await client.snapshot()
    for id in ids.reversed() {
        do {
            if snap?.workspaces.first(where: { $0.workspaceId == id })?.isLinkedWorktree == true {
                try await client.removeWorktree(id, force: true)
            } else {
                try await client.closeWorkspace(id)
            }
        } catch HerdrError.server(code: "workspace_not_found", _) {
            continue
        } catch {
            print("cleanup: \(id): \(error)")
        }
    }
    let folder = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".herdr/worktrees/\(herdrFolder)")
    try? FileManager.default.removeItem(at: folder)
}

/// WCAG contrast audit of every built-in theme (plus ~/.config/paca/themes) as Paca draws it.
/// Lists each pairing that needed correction with its ratio before and after.
func contrast(increased: Bool, verbose: Bool) {
    let dir = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".config/paca/themes")
    let user = ((try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? [])
        .filter { ["yaml", "yml"].contains($0.pathExtension) }
        .compactMap { url in (try? String(contentsOf: url, encoding: .utf8)).flatMap { Base16Scheme.load(yaml: $0, id: "user:" + url.deletingPathExtension().lastPathComponent) } }
    var failing = 0
    print("Contrast audit (\(increased ? "Increase contrast on" : "standard"), WCAG 2.x ratios, worst surface)")
    for scheme in Base16Scheme.builtIn + user {
        let palette = ThemePalette(scheme, increasedContrast: increased)
        let fixed = palette.checks.filter(\.wasAdjusted)
        failing += palette.failures.count
        print("\n\(scheme.name) [\(scheme.id)]: \(fixed.count) of \(palette.checks.count) colors corrected, \(palette.failures.count) failing")
        for check in palette.checks where verbose || check.wasAdjusted || check.after + 0.005 < check.minimum {
            let mark = check.after + 0.005 < check.minimum ? "FAIL" : check.wasAdjusted ? "fix " : "ok  "
            print(String(format: "  %@ %-22@ %@ %5.2f → %@ %5.2f  (min %.1f)",
                         mark, check.name as NSString, check.original.description, check.before,
                         check.adjusted.description, check.after, check.minimum))
        }
    }
    if failing > 0 { exit(1) }
}

do {
    switch command {
    case "contrast":
        contrast(increased: args.contains("--increased"), verbose: args.contains("--all"))
    case "snapshot":
        printSnapshot(try await HerdrClient(socketPath: socketPath).snapshot())
    case "watch":
        try await watch(HerdrClient(socketPath: socketPath))
    case "smoke":
        try await smoke(HerdrClient(socketPath: socketPath), session: session)
    case "frame":
        guard args.count > 1 else { fail("usage: paca-probe frame PANE_ID") }
        await frame(args[1])
    default:
        fail("unknown command \(command)")
    }
} catch {
    fail("\(error)")
}
