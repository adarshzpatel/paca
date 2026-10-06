import Foundation
import Testing
@testable import HerdrKit

@Test func decodesSnapshotFromHerdr090() throws {
    // Trimmed from a real `session.snapshot` result (herdr 0.9.0, protocol 22).
    let json = """
    {"version":"0.9.0","protocol":22,"focused_pane_id":"wP:p1",
     "workspaces":[{"active_tab_id":"wP:t1","agent_status":"working","focused":true,"label":"Developer","number":3,"pane_count":1,"tab_count":1,"workspace_id":"wP"}],
     "tabs":[{"agent_status":"working","focused":true,"label":"1","number":1,"pane_count":1,"tab_id":"wP:t1","workspace_id":"wP"}],
     "panes":[{"agent":"claude","agent_status":"working","cwd":"/Users/zero/Developer","focused":true,"foreground_cwd":"/Users/zero/Developer","pane_id":"wP:p1","revision":2,"tab_id":"wP:t1","terminal_id":"term_1","terminal_title_stripped":"Herdr macOS native GUI client","workspace_id":"wP"},
              {"agent_status":"unknown","cwd":"/tmp","focused":false,"pane_id":"wP:p2","tab_id":"wP:t1","terminal_id":"term_2","workspace_id":"wP"}]}
    """
    let snap = try HerdrJSON.decoder.decode(SessionSnapshot.self, from: Data(json.utf8))
    #expect(snap.protocolVersion == 22)
    #expect(snap.focusedPaneId == "wP:p1")
    #expect(snap.panes(in: snap.workspaces[0]).count == 2)
    #expect(snap.panes[0].displayName == "Herdr macOS native GUI client")
    #expect(snap.panes[1].displayName == "Shell")
}

@Test func unknownStatusFallsBack() throws {
    let status = try JSONDecoder().decode([AgentStatus].self, from: Data(#"["blocked","sleeping"]"#.utf8))
    #expect(status == [.blocked, .unknown])
    #expect(status[0].needsAttention)
}

@Test func agentNamesFromSnapshotAgentsWin() throws {
    // herdr keeps the `agent.start` / `agent.rename` name in `agents`, not on the pane.
    let json = """
    {"version":"0.9.0","protocol":22,"workspaces":[],"tabs":[],
     "panes":[{"agent":"claude","agent_status":"idle","focused":false,"pane_id":"w1:p4","tab_id":"w1:t2","terminal_id":"t4","terminal_title_stripped":"Claude Code","workspace_id":"w1"},
              {"agent_status":"unknown","focused":false,"label":"my shell","pane_id":"w1:p5","tab_id":"w1:t1","terminal_id":"t5","workspace_id":"w1"}],
     "agents":[{"pane_id":"w1:p4","name":"reviewer","agent":"claude","agent_status":"idle"}]}
    """
    let snap = try HerdrJSON.decoder.decode(SessionSnapshot.self, from: Data(json.utf8))
    #expect(snap.panes[0].agentName == "reviewer")
    #expect(snap.panes[0].displayName == "reviewer")
    #expect(snap.panes[1].displayName == "my shell")
}

@Test func attentionTransitionsOnlyReportChanges() throws {
    func snap(_ panes: [(String, String)]) throws -> SessionSnapshot {
        let rows = panes.map { id, status in
            #"{"agent":"claude","agent_status":"\#(status)","focused":false,"pane_id":"\#(id)","tab_id":"w1:t1","terminal_id":"t","workspace_id":"w1"}"#
        }
        let json = #"{"version":"0.9.0","protocol":22,"workspaces":[],"tabs":[],"panes":[\#(rows.joined(separator: ","))]}"#
        return try HerdrJSON.decoder.decode(SessionSnapshot.self, from: Data(json.utf8))
    }
    let first = try snap([("a", "working"), ("b", "blocked"), ("c", "idle")])
    #expect(first.attentionTransitions(since: nil).isEmpty)

    let second = try snap([("a", "blocked"), ("b", "blocked"), ("c", "done"), ("d", "done")])
    #expect(second.attentionTransitions(since: first).map(\.paneId) == ["a", "c", "d"])

    let third = try snap([("a", "done"), ("b", "blocked"), ("c", "done"), ("d", "done")])
    #expect(third.attentionTransitions(since: second).map(\.paneId) == ["a"])
}

@Test func statusChangesAndRules() throws {
    func snap(_ panes: [(String, String, String?)]) throws -> SessionSnapshot {
        let rows = panes.map { id, status, agent in
            let agentField = agent.map { #""agent":"\#($0)","# } ?? ""
            return #"{\#(agentField)"agent_status":"\#(status)","focused":false,"label":"\#(id)","pane_id":"\#(id)","tab_id":"w1:t1","terminal_id":"t","workspace_id":"w1"}"#
        }
        let json = #"{"version":"0.9.0","protocol":22,"workspaces":[],"tabs":[],"panes":[\#(rows.joined(separator: ","))]}"#
        return try HerdrJSON.decoder.decode(SessionSnapshot.self, from: Data(json.utf8))
    }
    let before = try snap([("reviewer", "working", "claude"), ("shell", "unknown", nil)])
    let after = try snap([("reviewer", "done", "claude"), ("shell", "idle", nil), ("fixer", "idle", "codex")])
    let changes = after.statusChanges(since: before)
    #expect(changes.map(\.paneId) == ["reviewer", "fixer"]) // shells never count
    #expect(changes[0].from == .working && changes[0].to == .done)
    #expect(changes[1].from == nil)

    var rule = AgentRule(source: "Reviewer", target: "fixer", message: "Fix what the review found.", outputLines: 2)
    #expect(rule.matches(changes[0]))
    #expect(!rule.matches(changes[1]))
    #expect(rule.prompt(sourceName: "reviewer", output: "a\nb\n") == "Fix what the review found.\n\n--- last 2 lines from reviewer ---\na\nb")
    rule.outputLines = 0
    #expect(rule.prompt(sourceName: "reviewer", output: "a") == "Fix what the review found.")
    rule.enabled = false
    #expect(!rule.matches(changes[0]))

    let same = try snap([("reviewer", "done", "claude")])
    #expect(same.statusChanges(since: after).isEmpty)
}
