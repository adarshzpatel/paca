import SwiftUI

struct SettingsView: View {
    @AppStorage(LiveTerminal.metalKey) private var metal = true
    @AppStorage(Notifier.enabledKey) private var notifications = true
    @AppStorage(AgentPanel.enabledKey) private var hotKey = true

    var body: some View {
        Form {
            Section {
                Toggle("Notify me when an agent needs me or finishes", isOn: $notifications)
                if !Notifier.isAvailable {
                    Text("Notifications work in the installed app (scripts/install.sh), not in a development build.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Toggle("⌥Space opens the agent panel from anywhere", isOn: $hotKey)
                    .onChange(of: hotKey) { _, on in AgentPanel.shared.setHotKey(on) }
            }

            Section {
                Picker("Terminal font", selection: Bindable(ThemeStore.shared).terminalFontChoice) {
                    if let g = ThemeStore.shared.ghostty, let family = g.fontFamily {
                        Text("Match Ghostty (\(family) \(Int(g.fontSize ?? 13)))").tag("ghostty")
                    }
                    Text("IBM Plex Mono (Paca)").tag("paca")
                }
                Toggle("Fast terminal rendering (Metal)", isOn: $metal)
                Text("Draws terminals on the GPU. Turn off if text looks wrong. Applies to panes you open next.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section {
                AppIconPicker()
            }

            Section {
                ThemeChoicePicker(choice: Bindable(ThemeStore.shared).choice)
                HStack {
                    Text("Base16 themes in ~/.config/paca/themes are added to this list.")
                        .font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button("Open Folder") { ThemeStore.openUserThemesFolder() }.controlSize(.small)
                }
            }

        }
        .formStyle(.grouped)
        .frame(width: 460)
        .fixedSize()
    }
}
