import Foundation

public enum HerdrError: Error, CustomStringConvertible, Sendable {
    case socket(String)
    case notRunning(path: String, errno: Int32)
    case disconnected
    case server(code: String, message: String)
    case decoding(String)

    /// Short text for the UI: herdr's own message for server errors.
    public var userMessage: String {
        if case .server(_, let message) = self, !message.isEmpty { return message }
        return description
    }

    public var description: String {
        switch self {
        case .socket(let msg): return msg
        case .notRunning(let path, let code): return "herdr is not running at \(path) (errno \(code))"
        case .disconnected: return "connection to herdr closed"
        case .server(let code, let message): return "\(code): \(message)"
        case .decoding(let msg): return "could not decode herdr response: \(msg)"
        }
    }
}

/// Agent lifecycle as herdr reports it. Unrecognized values decode as `.unknown`
/// so a newer server can't break an older client.
public enum AgentStatus: String, Codable, Sendable, CaseIterable {
    case idle, working, blocked, done, unknown

    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = AgentStatus(rawValue: raw) ?? .unknown
    }

    /// True when the agent is waiting on a human.
    public var needsAttention: Bool { self == .blocked || self == .done }
}

public struct Workspace: Codable, Hashable, Sendable, Identifiable {
    public let workspaceId: String
    public let label: String
    public let number: Int
    public let focused: Bool
    public let agentStatus: AgentStatus
    public let activeTabId: String?
    public let paneCount: Int
    public let tabCount: Int
    /// Present when the workspace runs inside a git checkout herdr knows about.
    public let worktree: WorkspaceWorktree?

    public var id: String { workspaceId }

    /// True for workspaces made by `worktree.create` / `worktree.open` on a linked worktree,
    /// which `worktree.remove` can delete. The main checkout is never removable.
    public var isLinkedWorktree: Bool { worktree?.isLinkedWorktree == true }
}

public struct WorkspaceWorktree: Codable, Hashable, Sendable {
    public let repoName: String?
    public let repoRoot: String?
    public let checkoutPath: String?
    public let isLinkedWorktree: Bool?
}

/// One entry of `worktree.list`.
public struct Worktree: Codable, Hashable, Sendable, Identifiable {
    public let path: String
    public let branch: String?
    public let isDetached: Bool?
    public let isLinkedWorktree: Bool?
    public let openWorkspaceId: String?

    public var id: String { path }
}

public struct Tab: Codable, Hashable, Sendable, Identifiable {
    public let tabId: String
    public let workspaceId: String
    public let label: String
    public let number: Int
    public let focused: Bool
    public let agentStatus: AgentStatus
    public let paneCount: Int

    public var id: String { tabId }
}

public struct Pane: Codable, Hashable, Sendable, Identifiable {
    public let paneId: String
    public let tabId: String
    public let workspaceId: String
    public let terminalId: String
    public let agent: String?
    public let displayAgent: String?
    public let agentStatus: AgentStatus
    public let cwd: String?
    public let foregroundCwd: String?
    public let focused: Bool
    public let label: String?
    public let title: String?
    public let terminalTitleStripped: String?
    public let revision: Int?
    /// Name given with `agent.start` or `agent.rename`. Not part of herdr's pane JSON;
    /// `SessionSnapshot` fills it in from the snapshot's `agents` list.
    public var agentName: String?
    /// Set from the snapshot's `agents` list while an `agent.start` is still launching.
    public var agentLaunchPending = false

    /// herdr's pane fields only. `agentName` and `agentLaunchPending` come from `agents`.
    enum CodingKeys: String, CodingKey {
        case paneId, tabId, workspaceId, terminalId, agent, displayAgent, agentStatus
        case cwd, foregroundCwd, focused, label, title, terminalTitleStripped, revision
    }

    public var id: String { paneId }

    /// Best human-readable name: explicit label, then agent name, then terminal title,
    /// then agent kind. Plain shells without a title are just "Shell"; their cwd shows elsewhere.
    public var displayName: String {
        if let label, !label.isEmpty { return label }
        if let agentName, !agentName.isEmpty { return agentName }
        if let t = terminalTitleStripped, !t.isEmpty { return t }
        if let a = displayAgent ?? agent { return a }
        return "Shell"
    }
}

/// One entry of the snapshot's `agents` list. Only the fields Paca reads.
public struct AgentEntry: Codable, Hashable, Sendable {
    public let paneId: String
    public let name: String?
    public let agent: String?
    /// True between `agent.start` and the agent being ready. herdr refuses renames meanwhile.
    public let launchPending: Bool?
}

public struct SessionSnapshot: Codable, Sendable {
    public let version: String
    public let protocolVersion: Int
    public let workspaces: [Workspace]
    public let tabs: [Tab]
    public let panes: [Pane]
    public let agents: [AgentEntry]
    public let focusedPaneId: String?

    enum CodingKeys: String, CodingKey {
        case version, workspaces, tabs, panes, agents, focusedPaneId
        case protocolVersion = "protocol"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        version = try c.decode(String.self, forKey: .version)
        protocolVersion = try c.decode(Int.self, forKey: .protocolVersion)
        workspaces = try c.decode([Workspace].self, forKey: .workspaces)
        tabs = try c.decode([Tab].self, forKey: .tabs)
        agents = try c.decodeIfPresent([AgentEntry].self, forKey: .agents) ?? []
        focusedPaneId = try c.decodeIfPresent(String.self, forKey: .focusedPaneId)
        let byPane = Dictionary(agents.map { ($0.paneId, $0) }, uniquingKeysWith: { first, _ in first })
        panes = try c.decode([Pane].self, forKey: .panes).map { pane in
            var pane = pane
            pane.agentName = byPane[pane.paneId]?.name
            pane.agentLaunchPending = byPane[pane.paneId]?.launchPending == true
            return pane
        }
    }

    public func panes(in workspace: Workspace) -> [Pane] {
        panes.filter { $0.workspaceId == workspace.workspaceId }
    }

    /// Agent panes that just started needing a person: they are `blocked` or `done` now and
    /// were in another state (or didn't exist) in `previous`. Empty without a previous snapshot,
    /// so connecting or switching sessions never replays old states as new.
    public func attentionTransitions(since previous: SessionSnapshot?) -> [Pane] {
        let ids = Set(statusChanges(since: previous).filter { $0.to.needsAttention }.map(\.paneId))
        return panes.filter { ids.contains($0.paneId) }
    }

    /// Every agent pane whose status differs from `previous`, including agents that appeared.
    /// Empty without a previous snapshot. Feeds the activity log and rules.
    public func statusChanges(since previous: SessionSnapshot?) -> [StatusChange] {
        guard let previous else { return [] }
        let before = Dictionary(previous.panes.map { ($0.paneId, $0.agentStatus) }, uniquingKeysWith: { first, _ in first })
        return panes.compactMap { pane in
            guard pane.agent != nil, before[pane.paneId] != pane.agentStatus else { return nil }
            return StatusChange(
                paneId: pane.paneId,
                workspaceId: pane.workspaceId,
                name: pane.displayName,
                kind: pane.displayAgent ?? pane.agent,
                from: before[pane.paneId],
                to: pane.agentStatus
            )
        }
    }
}

/// An agent's status moving from one value to another between two snapshots.
public struct StatusChange: Codable, Hashable, Sendable {
    public let paneId: String
    public let workspaceId: String
    public let name: String
    public let kind: String?
    /// Nil when the agent wasn't in the previous snapshot.
    public let from: AgentStatus?
    public let to: AgentStatus

    public init(paneId: String, workspaceId: String, name: String, kind: String?, from: AgentStatus?, to: AgentStatus) {
        self.paneId = paneId
        self.workspaceId = workspaceId
        self.name = name
        self.kind = kind
        self.from = from
        self.to = to
    }
}

/// "When `source` becomes `trigger`, prompt `target` with `message`." Agents are matched by name
/// (case-insensitive) within the session or machine on screen, because pane ids change when an
/// agent restarts but names you give them don't.
public struct AgentRule: Codable, Hashable, Sendable, Identifiable {
    public var id = UUID()
    public var enabled = true
    public var source: String
    public var trigger: AgentStatus = .done
    public var target: String
    public var message: String
    /// Lines of the source agent's recent output to append. 0 sends the message alone.
    public var outputLines = 40

    public init(source: String, trigger: AgentStatus = .done, target: String, message: String, outputLines: Int = 40) {
        self.source = source
        self.trigger = trigger
        self.target = target
        self.message = message
        self.outputLines = outputLines
    }

    /// True when `change` is the source agent arriving at the trigger state.
    public func matches(_ change: StatusChange) -> Bool {
        enabled && change.to == trigger && change.from != trigger
            && change.name.compare(source, options: .caseInsensitive) == .orderedSame
    }

    /// The text sent to the target: the message, then the source's output if asked for.
    public func prompt(sourceName: String, output: String?) -> String {
        let output = output?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard outputLines > 0, !output.isEmpty else { return message }
        return "\(message)\n\n--- last \(outputLines) lines from \(sourceName) ---\n\(output)"
    }
}

/// One pushed event from `events.subscribe`. `data` is the raw JSON payload,
/// decode it with `decode(_:)` once `kind` tells you the shape.
public struct HerdrEvent: Sendable {
    public let kind: String
    public let data: Data

    public func decode<T: Decodable>(_ type: T.Type) throws -> T {
        try HerdrJSON.decoder.decode(T.self, from: data)
    }
}

public struct PaneStatusChange: Decodable, Sendable {
    public let paneId: String
    public let workspaceId: String
    public let agentStatus: AgentStatus
    public let agent: String?
}

enum HerdrJSON {
    static var decoder: JSONDecoder {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        return d
    }
}
