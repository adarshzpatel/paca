import AppKit
import HerdrKit
import Observation
import SwiftUI

// Orchestrator groundwork: every agent status change goes into a log on disk, and rules
// ("when reviewer is done, prompt fixer") run on top of the same changes.

/// One line of the activity log.
struct ActivityEvent: Codable, Identifiable, Hashable {
    var id = UUID()
    let date: Date
    /// Machine label, or session name for local sessions.
    let target: String
    let paneId: String
    let agent: String
    let kind: String?
    let workspace: String?
    let from: AgentStatus?
    let to: AgentStatus?
    /// Set for rule runs: what happened, in words.
    var note: String?
    var failed = false
}

/// Appends events to `~/Library/Application Support/Paca/activity.jsonl` and keeps the
/// newest 1,000 in memory. The file is trimmed to its newest 2,000 lines past 5 MB.
@MainActor
@Observable
final class ActivityLog {
    static let shared = ActivityLog()
    private(set) var events: [ActivityEvent] = []

    @ObservationIgnored private let url: URL
    private static let memoryLimit = 1_000

    init(folder: URL = ActivityLog.supportFolder) {
        url = folder.appendingPathComponent("activity.jsonl")
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        events = Self.read(url).suffix(Self.memoryLimit)
    }

    nonisolated static var supportFolder: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Paca", isDirectory: true)
    }

    func append(_ event: ActivityEvent) {
        events.append(event)
        if events.count > Self.memoryLimit { events.removeFirst(events.count - Self.memoryLimit) }
        guard var line = try? Self.encoder.encode(event) else { return }
        line.append(0x0A)
        if let handle = try? FileHandle(forWritingTo: url) {
            handle.seekToEndOfFile()
            handle.write(line)
            try? handle.close()
        } else {
            try? line.write(to: url)
        }
        trimIfLarge()
    }

    /// Time the agent spent in the state it just left: since its previous event on this target.
    func duration(before event: ActivityEvent) -> TimeInterval? {
        guard let index = events.lastIndex(of: event) else { return nil }
        return events[..<index].last { $0.paneId == event.paneId && $0.target == event.target && $0.note == nil }
            .map { event.date.timeIntervalSince($0.date) }
    }

    private func trimIfLarge() {
        let size = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int) ?? 0
        guard size > 5_000_000 else { return }
        let kept = Self.read(url).suffix(2_000)
        let data = kept.compactMap { try? Self.encoder.encode($0) }.map { $0 + Data([0x0A]) }.reduce(Data(), +)
        try? data.write(to: url, options: .atomic)
    }

    private static func read(_ url: URL) -> [ActivityEvent] {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return [] }
        return text.split(separator: "\n").compactMap { try? decoder.decode(ActivityEvent.self, from: Data($0.utf8)) }
    }

    private static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return e
    }()

    private static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()
}

/// Rules, saved to `~/Library/Application Support/Paca/rules.json`.
@MainActor
@Observable
final class RuleBook {
    static let shared = RuleBook()
    var rules: [AgentRule] = [] {
        didSet { save() }
    }

    @ObservationIgnored private let url = ActivityLog.supportFolder.appendingPathComponent("rules.json")

    init() {
        if let data = try? Data(contentsOf: url), let saved = try? JSONDecoder().decode([AgentRule].self, from: data) {
            rules = saved
        }
    }

    private func save() {
        try? FileManager.default.createDirectory(at: ActivityLog.supportFolder, withIntermediateDirectories: true)
        if let data = try? JSONEncoder().encode(rules) { try? data.write(to: url, options: .atomic) }
    }
}

/// Logs every status change and runs the rules that match it.
@MainActor
final class Orchestrator {
    static let shared = Orchestrator()
    private weak var store: HerdrStore?
    private var lastFired: [UUID: Date] = [:]
    /// A rule waits this long before it may fire again, so two rules can't ping-pong forever.
    static let cooldown: TimeInterval = 60

    func attach(to store: HerdrStore) {
        self.store = store
        store.onStatusChanges = { [weak self] changes in self?.handle(changes) }
    }

    private func handle(_ changes: [StatusChange]) {
        guard let store else { return }
        for change in changes {
            ActivityLog.shared.append(ActivityEvent(
                date: Date(), target: store.targetName, paneId: change.paneId, agent: change.name,
                kind: change.kind, workspace: store.workspaceTitle(id: change.workspaceId),
                from: change.from, to: change.to
            ))
            for rule in RuleBook.shared.rules where rule.matches(change) {
                fire(rule, for: change)
            }
        }
    }

    private func fire(_ rule: AgentRule, for change: StatusChange) {
        guard let store else { return }
        if let last = lastFired[rule.id], Date().timeIntervalSince(last) < Self.cooldown {
            record(rule, change, "skipped: fired less than a minute ago", failed: true)
            return
        }
        lastFired[rule.id] = Date()
        guard let target = store.agent(named: rule.target) else {
            record(rule, change, "no agent named \(rule.target) on \(store.targetName)", failed: true)
            return
        }
        Task {
            do {
                let output = rule.outputLines > 0 ? try? await store.recentOutput(of: change.paneId, lines: rule.outputLines) : nil
                try await store.prompt(target, text: rule.prompt(sourceName: change.name, output: output))
                record(rule, change, "prompted \(target.displayName)", failed: false)
            } catch {
                let message = (error as? HerdrError)?.userMessage ?? "\(error)"
                record(rule, change, "couldn't prompt \(target.displayName): \(message)", failed: true)
            }
        }
    }

    private func record(_ rule: AgentRule, _ change: StatusChange, _ note: String, failed: Bool) {
        guard let store else { return }
        var event = ActivityEvent(
            date: Date(), target: store.targetName, paneId: change.paneId, agent: change.name,
            kind: change.kind, workspace: store.workspaceTitle(id: change.workspaceId), from: nil, to: nil
        )
        event.note = "Rule: when \(rule.source) is \(rule.trigger.rawValue), prompt \(rule.target). \(note.prefix(1).uppercased() + note.dropFirst())."
        event.failed = failed
        ActivityLog.shared.append(event)
    }
}

// MARK: - Views

/// Sidebar list of recent activity on the current session or machine, newest first.
struct ActivityList: View {
    @Environment(HerdrStore.self) private var store
    @State private var showRules = false
    private let log = ActivityLog.shared

    private var events: [ActivityEvent] {
        log.events.filter { $0.target == store.targetName }.suffix(200).reversed()
    }

    var body: some View {
        HStack {
            Text("Activity")
                .font(.system(size: 13.5))
                .foregroundStyle(Theme.text3)
            Spacer()
            Button("Rules…") { showRules = true }
                .buttonStyle(.plain)
                .pointerCursor()
                .font(.system(size: 12.5))
                .foregroundStyle(Theme.accent)
        }
        .padding(.horizontal, 10)
        .frame(height: 30)
        .sheet(isPresented: $showRules) { RulesSheet() }

        if events.isEmpty {
            Text("Agent status changes on \(store.targetName) show up here as they happen.")
                .font(.system(size: 12.5))
                .foregroundStyle(Theme.text3)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
        }
        ForEach(events) { event in
            Button { open(event) } label: { row(event) }
                .buttonStyle(RowButtonStyle(selected: store.selectedPaneId == event.paneId))
        }
    }

    private func row(_ event: ActivityEvent) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                if let note = event.note {
                    PhIcon(event.failed ? .warning : .lightning, size: 10.5, weight: .fill)
                        .foregroundStyle(event.failed ? Theme.danger : Theme.accent)
                    Text(note).font(.system(size: 12.5)).foregroundStyle(Theme.text).lineLimit(3)
                } else {
                    StatusGlyph(status: event.to ?? .unknown, size: 11)
                    Text(event.agent).font(.system(size: 13.5)).foregroundStyle(Theme.text).lineLimit(1)
                    Text(transition(event)).font(.system(size: 12.5)).foregroundStyle(Theme.text3).lineLimit(1)
                }
                Spacer(minLength: 4)
            }
            Text(detail(event))
                .font(.system(size: 11.5))
                .foregroundStyle(Theme.text3)
                .lineLimit(1)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }

    private func transition(_ event: ActivityEvent) -> String {
        guard let to = event.to else { return "" }
        return event.from.map { "\($0.rawValue) → \(to.rawValue)" } ?? "started, \(to.rawValue)"
    }

    /// "12:41 · 3m working · reviewer's workspace"
    private func detail(_ event: ActivityEvent) -> String {
        var parts = [event.date.formatted(date: .omitted, time: .shortened)]
        if event.note == nil, let from = event.from, let seconds = log.duration(before: event) {
            parts.append("\(Self.format(seconds)) \(from.rawValue)")
        }
        if let workspace = event.workspace { parts.append(workspace) }
        return parts.joined(separator: " · ")
    }

    static func format(_ seconds: TimeInterval) -> String {
        let s = Int(seconds)
        if s < 60 { return "\(s)s" }
        if s < 3600 { return "\(s / 60)m" }
        return "\(s / 3600)h \(s % 3600 / 60)m"
    }

    private func open(_ event: ActivityEvent) {
        guard store.pane(id: event.paneId) != nil else { return }
        store.selectedPaneId = event.paneId
    }
}

/// List, toggle, delete and add rules.
private struct RulesSheet: View {
    @Environment(HerdrStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var book = RuleBook.shared
    @State private var draft = AgentRule(source: "", target: "", message: "")

    private var agentNames: [String] { Array(Set(store.panes.filter(\.isAgent).map(\.displayName))).sorted() }
    private var canAdd: Bool {
        !draft.source.trimmingCharacters(in: .whitespaces).isEmpty
            && !draft.target.trimmingCharacters(in: .whitespaces).isEmpty
            && !draft.message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && draft.source.caseInsensitiveCompare(draft.target) != .orderedSame
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Rules").font(.system(size: 15, weight: .semibold))
            Text("When one agent reaches a state, Paca prompts another. Agents are matched by name on whichever session or machine Paca is showing. A rule waits a minute before it can fire again.")
                .font(.system(size: 12)).foregroundStyle(Theme.text3)
                .fixedSize(horizontal: false, vertical: true)

            if book.rules.isEmpty {
                Text("No rules yet.").font(.system(size: 12.5)).foregroundStyle(Theme.text3)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach($book.rules) { $rule in
                            HStack(alignment: .top, spacing: 10) {
                                Toggle("", isOn: $rule.enabled).labelsHidden().toggleStyle(.switch).controlSize(.small)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("When \(rule.source) is \(rule.trigger.rawValue), prompt \(rule.target)")
                                        .font(.system(size: 13, weight: .medium))
                                    Text(rule.message + (rule.outputLines > 0 ? " (+ last \(rule.outputLines) lines)" : ""))
                                        .font(.system(size: 12)).foregroundStyle(Theme.text3).lineLimit(2)
                                }
                                Spacer()
                                Button { book.rules.removeAll { $0.id == rule.id } } label: {
                                    PhIcon(.trash, size: 13).foregroundStyle(Theme.text3)
                                }
                                .buttonStyle(.plain)
                                .pointerCursor()
                                .accessibilityLabel("Delete rule")
                            }
                        }
                    }
                }
                .frame(maxHeight: 180)
            }

            Divider()

            Text("New rule").font(.system(size: 13, weight: .semibold))
            Form {
                nameField("When agent", text: $draft.source)
                Picker("becomes", selection: $draft.trigger) {
                    Text("done").tag(AgentStatus.done)
                    Text("blocked").tag(AgentStatus.blocked)
                    Text("idle").tag(AgentStatus.idle)
                }
                nameField("prompt agent", text: $draft.target)
                TextField("with", text: $draft.message, prompt: Text("Review the changes and fix what's broken."), axis: .vertical)
                    .lineLimit(2...5)
                Picker("and include", selection: $draft.outputLines) {
                    Text("nothing else").tag(0)
                    Text("its last 20 lines").tag(20)
                    Text("its last 40 lines").tag(40)
                    Text("its last 100 lines").tag(100)
                }
            }
            .formStyle(.columns)

            HStack {
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Add Rule") {
                    book.rules.append(draft)
                    draft = AgentRule(source: "", target: "", message: "")
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!canAdd)
            }
        }
        .padding(20)
        .frame(width: 480)
    }

    /// Free text, with the agents on screen offered in a menu.
    private func nameField(_ label: String, text: Binding<String>) -> some View {
        HStack(spacing: 6) {
            TextField(label, text: text, prompt: Text("agent name"))
            if !agentNames.isEmpty {
                Menu {
                    ForEach(agentNames, id: \.self) { name in Button(name) { text.wrappedValue = name } }
                } label: {
                    PhIcon(.caretDown, size: 11)
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .pointerCursor()
            }
        }
    }
}
