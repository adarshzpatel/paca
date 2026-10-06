import HerdrKit
import SwiftUI

/// Menu bar text: blocked, working and unseen-done counts. Empty when nothing is active.
struct MenuBarLabel: View {
    let store: HerdrStore

    var body: some View {
        let blocked = store.count(.blocked)
        let working = store.count(.working)
        let done = store.count(.done)
        let parts = [
            blocked > 0 ? "⚑\(blocked)" : nil,
            working > 0 ? "◐\(working)" : nil,
            done > 0 ? "✓\(done)" : nil,
        ].compactMap { $0 }

        HStack(spacing: 4) {
            Image(nsImage: Brand.menuBarSymbol)
                .opacity(store.connectionError != nil ? 0.45 : 1)
            if !parts.isEmpty { Text(parts.joined(separator: " ")) }
        }
    }
}

struct MenuBarPanel: View {
    @Environment(HerdrStore.self) private var store
    /// Runs after a row or "Open Paca" opens the main window, e.g. to hide the floating panel.
    var onOpen: () -> Void = {}

    private var agents: [Pane] { store.panes.filter(\.isAgent) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Image(nsImage: Brand.menuBarSymbol)
                    .renderingMode(.template)
                    .foregroundStyle(Color(nsColor: .secondaryLabelColor))
                Wordmark(height: 14)
                Spacer()
                Circle().fill(Color(nsColor: store.connectionError == nil ? .systemGreen : .systemRed)).frame(width: 7, height: 7)
            }
            .padding(.horizontal, 14)
            .frame(height: 40)

            Color(nsColor: .separatorColor).frame(height: 1)

            VStack(alignment: .leading, spacing: 1) {
                if let error = store.connectionError {
                    note(error)
                } else if agents.isEmpty {
                    note("No agents running")
                } else {
                    group("Needs you", agents.filter { $0.agentStatus.needsAttention })
                    group("Working", agents.filter { $0.agentStatus == .working })
                    group("Idle", agents.filter { $0.agentStatus == .idle || $0.agentStatus == .unknown })
                }
            }
            .padding(6)

            Color(nsColor: .separatorColor).frame(height: 1)

            Button { open(nil) } label: {
                HStack {
                    Text("Open Paca").font(.system(size: 13)).foregroundStyle(Color(nsColor: .labelColor))
                    Spacer()
                    Kbd("⌘O")
                }
                .padding(.horizontal, 10)
                .frame(height: 30)
                .contentShape(Rectangle())
            }
            .buttonStyle(RowButtonStyle())
            .keyboardShortcut("o")
            .padding(6)
        }
        .frame(width: 340)
        // The panel sits on the system window material, so draw with system colors to keep
        // contrast in light and dark mode whatever Paca theme is picked.
        .environment(\.systemColors, true)
    }

    private func note(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 12.5))
            .foregroundStyle(Color(nsColor: .secondaryLabelColor))
            .padding(10)
    }

    @ViewBuilder
    private func group(_ title: String, _ panes: [Pane]) -> some View {
        if !panes.isEmpty {
            Text(title)
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(Color(nsColor: .secondaryLabelColor))
                .padding(.horizontal, 10)
                .padding(.top, 8)
                .padding(.bottom, 2)
            ForEach(panes) { pane in
                Button { open(pane.paneId) } label: {
                    HStack(spacing: 10) {
                        StatusGlyph(status: pane.agentStatus)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(pane.displayName)
                                .font(.system(size: 13, weight: pane.agentStatus == .blocked ? .semibold : .regular))
                                .foregroundStyle(Color(nsColor: .labelColor))
                                .lineLimit(1)
                            Text([pane.kind, store.workspaceTitle(id: pane.workspaceId)].compactMap { $0 }.joined(separator: " · "))
                                .font(.system(size: 11.5))
                                .foregroundStyle(Color(nsColor: .secondaryLabelColor))
                                .lineLimit(1)
                        }
                        Spacer(minLength: 4)
                    }
                    .padding(.horizontal, 10)
                    .frame(height: 42)
                    .contentShape(Rectangle())
                }
                .buttonStyle(RowButtonStyle())
            }
        }
    }

    private func open(_ paneId: String?) {
        MainWindow.show(paneId: paneId, store: store)
        onOpen()
    }
}
