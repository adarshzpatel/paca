import AppKit
import HerdrKit
import SwiftUI

/// Slack-style far-left rail: view switches on top, then one tile per running herdr session.
struct Rail: View {
    @Environment(HerdrStore.self) private var store
    @State private var stopping: HerdrSession?
    @State private var deleting: HerdrSession?
    @State private var naming = false
    @State private var newName = ""
    @State private var addingMachine = false
    @State private var removingMachine: HerdrMachine?

    private var running: [HerdrSession] { store.sessions.filter(\.running) }
    private var machines: [HerdrMachine] { store.machines.filter(\.enabled) }
    private var stopped: [HerdrSession] { store.sessions.filter { !$0.running } }

    var body: some View {
        VStack(spacing: Theme.space) {
            RailButton(icon: .house, help: "Home", selected: store.sidebarMode == .home) {
                store.sidebarMode = .home
            }
            RailButton(
                icon: .tray, help: "Needs you",
                selected: store.sidebarMode == .inbox,
                badge: store.needsYou.count
            ) {
                store.sidebarMode = .inbox
            }
            RailButton(icon: .history, help: "Activity and rules", selected: store.sidebarMode == .activity) {
                store.sidebarMode = .activity
            }

            Rectangle().fill(Theme.hairline).frame(width: 24, height: 1)

            ForEach(running) { session in
                let current = !store.isRemote && session.name == store.sessionName
                SessionTile(
                    initial: session.isDefault ? "D" : String(session.name.prefix(1)).uppercased(),
                    name: sessionLabel(session, current: current),
                    selected: current,
                    tint: Theme.hashedTint("session/\(session.name)"),
                    textTint: Theme.hashedTint("session/\(session.name)", text: true)
                ) {
                    store.switchSession(to: session.name)
                }
                .contextMenu {
                    Button("Stop Session…", role: .destructive) { stopping = session }
                }
            }

            if !machines.isEmpty {
                Rectangle().fill(Theme.hairline).frame(width: 16, height: 1)
                RailCaption(text: "Machines")
                ForEach(machines) { machine in
                    let current = store.machine?.id == machine.id
                    SessionTile(
                        initial: String(machine.label.prefix(1)).uppercased(),
                        name: machineLabel(machine, current: current),
                        selected: current,
                        tint: Theme.hashedTint("machine/\(machine.id)"),
                        textTint: Theme.hashedTint("machine/\(machine.id)", text: true),
                        remote: true,
                        problem: current && store.connectionError != nil
                    ) {
                        store.switchMachine(to: machine)
                    }
                    .contextMenu {
                        if current { Button("Reconnect") { store.reconnect() } }
                        Button("Remove Machine…", role: .destructive) { removingMachine = machine }
                    }
                }
            }
            sessionMenu

            Spacer()

            ThemeMenu(size: 38, fontSize: 15, tipEdge: .trailing)
                .padding(.bottom, 2)

            SettingsLink {
                PhIcon(.gear, size: 15)
                    .foregroundStyle(Theme.text3)
                    .frame(width: 38, height: 38)
                    .contentShape(Rectangle())
            }
            .buttonStyle(RowButtonStyle())
            .hoverTip("Settings", shortcut: "⌘,", edge: .trailing)
            .accessibilityLabel("Settings")
            .padding(.bottom, Theme.space)
        }
        .padding(.top, Theme.space)
        .frame(width: RootView.railWidth)
        .task {
            await store.refreshSessions()
            await store.refreshMachines()
        }
        .sheet(isPresented: $addingMachine) { AddMachineSheet() }
        .confirmationDialog(
            removingMachine.map { "Remove \($0.label)?" } ?? "",
            isPresented: Binding(get: { removingMachine != nil }, set: { if !$0 { removingMachine = nil } }),
            presenting: removingMachine
        ) { machine in
            Button("Remove Machine", role: .destructive) { Task { await store.removeMachine(machine) } }
        } message: { machine in
            Text("Paca and herdr forget \(machine.target). herdr keeps running on it, with its agents.")
        }
        .confirmationDialog(
            stopping.map { "Stop the \($0.name) session?" } ?? "",
            isPresented: Binding(get: { stopping != nil }, set: { if !$0 { stopping = nil } }),
            presenting: stopping
        ) { session in
            Button("Stop Session", role: .destructive) { Task { await store.stopSession(session) } }
        } message: { session in
            Text(stopWarning(for: session))
        }
        .confirmationDialog(
            deleting.map { "Delete the \($0.name) session?" } ?? "",
            isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }),
            presenting: deleting
        ) { session in
            Button("Delete Session", role: .destructive) { Task { await store.deleteSession(session) } }
        } message: { _ in
            Text("This removes the session and its saved layout for good.")
        }
        .alert("New session", isPresented: $naming) {
            TextField("Name", text: $newName)
            Button("Cancel", role: .cancel) {}
            Button("Create") { Task { await store.newSession(named: newName) } }
        } message: {
            Text("Starts a separate herdr server with its own workspaces. Letters, numbers, '.', '_' and '-'.")
        }
    }

    /// "+" menu: new session, plus start or delete for the stopped ones.
    private var sessionMenu: some View {
        Menu {
            Button("New Session…") {
                newName = ""
                naming = true
            }
            Button("Add Machine…") { addingMachine = true }
            if !stopped.isEmpty {
                Section("Stopped") {
                    ForEach(stopped) { session in
                        Menu(session.name) {
                            Button("Start") { Task { await store.startSession(session) } }
                            Button("Delete…", role: .destructive) { deleting = session }
                        }
                    }
                }
            }
        } label: {
            PhIcon(.plus, size: 13)
                .foregroundStyle(Theme.text3)
                .frame(width: 38, height: 38)
                .contentShape(Rectangle())
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .pointerCursor()
        .hoverTip("New session, add a machine, or start a stopped session", edge: .trailing)
        .accessibilityLabel("Sessions and machines")
    }

    /// What a session tile is, in words: the rail only has room for a letter.
    private func sessionLabel(_ session: HerdrSession, current: Bool) -> String {
        let name = session.isDefault ? "Default herdr session" : "herdr session “\(session.name)”"
        guard current else { return "\(name)\nClick to switch · right-click to stop" }
        let agents = store.panes.filter(\.isAgent).count
        return "\(name) · showing now\n\(store.workspaces.count) workspaces, \(agents) agent\(agents == 1 ? "" : "s")"
    }

    private func machineLabel(_ machine: HerdrMachine, current: Bool) -> String {
        let state = !current ? "Click to connect" : store.connectionError != nil ? "Can't connect, right-click to retry" : "Showing now"
        return "Machine \(machine.label) (\(machine.target))\n\(state)"
    }

    private func stopWarning(for session: HerdrSession) -> String {
        guard session.name == store.sessionName else {
            return "Every agent and shell in it ends."
        }
        let agents = store.panes.filter(\.isAgent).count
        let busy = store.panes.filter { $0.isAgent && ($0.agentStatus == .working || $0.agentStatus == .blocked) }.count
        return "This ends \(agents) agent\(agents == 1 ? "" : "s") (\(busy) mid-task) and every shell. Paca switches to the default session."
    }
}

private struct RailButton: View {
    let icon: Icon
    let help: String
    let selected: Bool
    var badge = 0
    let action: () -> Void
    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            PhIcon(icon, size: 15, weight: selected ? .fill : .bold)
                .foregroundStyle(selected ? Theme.text : Theme.text3)
                .frame(width: 38, height: 38)
                .background(RoundedRectangle(cornerRadius: 10).fill(selected ? Theme.washStrong : hovered ? Theme.wash : .clear))
                .overlay(alignment: .topTrailing) {
                    if badge > 0 {
                        Circle().fill(Theme.blocked).frame(width: 8, height: 8).offset(x: -6, y: 6)
                    }
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
        .pointerCursor()
        .hoverTip(badge > 0 ? "\(help) (\(badge))" : help, edge: .trailing)
        .accessibilityLabel(badge > 0 ? "\(help), \(badge)" : help)
    }
}

/// One running herdr session or saved machine. Click to switch; the current one gets the
/// outline. Machines carry a small network badge, and a red dot while their connection fails.
private struct SessionTile: View {
    let initial: String
    let name: String
    let selected: Bool
    /// The session's color: a soft fill behind its letter.
    let tint: Color
    /// The same color pushed to text contrast, for the letter.
    let textTint: Color
    var remote = false
    var problem = false
    let action: () -> Void
    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            Text(initial)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(textTint)
                .frame(width: 38, height: 38)
                .background(RoundedRectangle(cornerRadius: 10).fill(tint.opacity(selected || hovered ? 0.28 : 0.16)))
                .overlay {
                    if selected {
                        // On the tile's own edge, so ring and tile share one outline.
                        RoundedRectangle(cornerRadius: 10).strokeBorder(Theme.accent, lineWidth: 2)
                    }
                }
                .overlay(alignment: .bottomTrailing) {
                    if remote {
                        PhIcon(problem ? .warningCircle : .globe, size: 9, weight: problem ? .fill : .bold)
                            .foregroundStyle(problem ? Theme.danger : Theme.text2)
                            .padding(2)
                            .background(Circle().fill(Theme.chrome))
                            .offset(x: 4, y: 4)
                    }
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
        .pointerCursor()
        .hoverTip(name, edge: .trailing)
        .accessibilityLabel(name.replacingOccurrences(of: "\n", with: ", "))
    }
}

/// SSH target and label for a new machine. herdr installs itself on the machine if needed.
private struct AddMachineSheet: View {
    @Environment(HerdrStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var target = ""
    @State private var label = ""
    @State private var adding = false
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Add machine").font(.system(size: 15, weight: .semibold))
            Form {
                TextField("SSH target", text: $target, prompt: Text("devbox or me@host.example.com"))
                TextField("Label", text: $label, prompt: Text(target.isEmpty ? "Label" : target))
            }
            .formStyle(.columns)
            Text("Paca connects with your SSH keys or ssh-agent (no passwords). If the machine doesn't have the same herdr version, herdr installs it to ~/.local/bin there.")
                .font(.system(size: 12)).foregroundStyle(Theme.text3)
                .fixedSize(horizontal: false, vertical: true)
            if let error {
                Text(error).font(.system(size: 12)).foregroundStyle(Theme.danger)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack {
                if adding { ProgressView().controlSize(.small); Text("Preparing herdr…").font(.system(size: 12)).foregroundStyle(Theme.text3) }
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Add") { add() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(adding || target.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 420)
    }

    private func add() {
        adding = true
        error = nil
        Task {
            let ok = await store.addMachine(target: target, label: label)
            adding = false
            if ok {
                dismiss()
            } else {
                error = store.actionError
                store.actionError = nil
            }
        }
    }
}

extension NSColor {
    var asColor: Color { Color(nsColor: self) }
}

/// Tiny group label in the rail, so a column of letters reads as "these are sessions".
private struct RailCaption: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 9, weight: .semibold))
            .foregroundStyle(Theme.text4)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .frame(width: 52)
            .accessibilityAddTraits(.isHeader)
    }
}

