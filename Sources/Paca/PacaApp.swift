import AppKit
import Carbon.HIToolbox
import HerdrKit
import SwiftUI
import UserNotifications

final class AppDelegate: NSObject, NSApplicationDelegate {
    /// Set by `PacaApp` before launch finishes, so the delegate can wire app-wide services.
    @MainActor static var store: HerdrStore?

    func applicationWillTerminate(_ notification: Notification) {
        MainActor.assumeIsolated { AppDelegate.store?.shutDown() }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Needed when launched as a bare SwiftPM executable instead of a bundled .app.
        NSApp.setActivationPolicy(.regular)
        // The Dock icon picked in Settings, or the bundle's own (see AppIcon).
        AppIcon.apply()
        NSApp.activate(ignoringOtherApps: true)
        ThemeStore.shared.resolve()
        MainThreadWatchdog.start()
        WindowSnapshot.scheduleIfRequested()
        MainActor.assumeIsolated {
            if let store = AppDelegate.store {
                Notifier.shared.attach(to: store)
                Orchestrator.shared.attach(to: store)
                AgentPanel.shared.attach(to: store)
            }
        }
    }
}

@main
struct PacaApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    init() { Brand.registerFonts() }
    @State private var store: HerdrStore = {
        let session = PacaApp.argument("--session")
            ?? UserDefaults.standard.string(forKey: HerdrStore.lastSessionKey)
            ?? "default"
        let store = HerdrStore(session: session)
        // `--select w1:p1,w1:p2` opens each as a tab and focuses the last.
        for id in (PacaApp.argument("--select") ?? "").split(separator: ",") { store.selectedPaneId = String(id) }
        store.launchMachine = PacaApp.argument("--machine")
        store.launchSessionGiven = PacaApp.argument("--session") != nil
        store.remembersTarget = ["--session", "--machine", "--snapshot"].allSatisfy { PacaApp.argument($0) == nil }
        if PacaApp.argument("--view") == "home" { store.sidebarMode = .home }
        if PacaApp.argument("--view") == "activity" { store.sidebarMode = .activity }
        if PacaApp.argument("--view") == "inbox" { store.sidebarMode = .inbox }
        // `--new-agent`: open New agent once the window is up, as a click would.
        if PacaApp.argument("--new-agent") != nil {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { store.newAgentRequest = .init(workspace: nil) }
        }
        AppDelegate.store = store
        return store
    }()

    var body: some Scene {
        Window("Paca", id: "main") {
            Themed { RootView() }
                .environment(store)
                .modifier(RegistersMainWindowOpener())
                .frame(minWidth: 960, minHeight: 600)
                .task { store.start() }
        }
        .defaultSize(width: 1280, height: 820)
        .windowStyle(.hiddenTitleBar)

        Settings {
            Themed { SettingsView() }
        }

        MenuBarExtra {
            Themed { MenuBarPanel() }
                .environment(store)
                .task { store.start() }
        } label: {
            MenuBarLabel(store: store)
        }
        .menuBarExtraStyle(.window)
    }

    /// Launch flags for scripted runs:
    /// `--session NAME` targets a named herdr session, `--machine LABEL` a saved SSH machine,
    /// `--select PANE` opens a pane, `--view activity|inbox` picks the sidebar view.
    static func argument(_ flag: String) -> String? {
        let args = CommandLine.arguments
        guard let i = args.firstIndex(of: flag), i + 1 < args.count else { return nil }
        return args[i + 1]
    }
}

// MARK: - Opening the main window from anywhere

/// SwiftUI's `openWindow` only exists inside a scene. Notifications and the floating panel live
/// outside one, so the main window registers its opener here when it first appears.
@MainActor
enum MainWindow {
    static var opener: (() -> Void)?

    /// Brings Paca forward with `paneId` selected (switching session first if needed).
    static func show(paneId: String?, session: String? = nil, store: HerdrStore) {
        if let session, session != store.sessionName || store.isRemote { store.switchSession(to: session) }
        if let paneId { store.selectedPaneId = paneId }
        store.sidebarMode = .home
        if let window = NSApp.windows.first(where: { $0.identifier?.rawValue.contains("main") == true }) {
            window.makeKeyAndOrderFront(nil)
        } else {
            opener?()
        }
        NSApp.activate(ignoringOtherApps: true)
    }
}

private struct RegistersMainWindowOpener: ViewModifier {
    @Environment(\.openWindow) private var openWindow

    func body(content: Content) -> some View {
        content.onAppear {
            MainWindow.opener = { openWindow(id: "main") }
        }
    }
}

// MARK: - Notifications

/// Posts a notification when an agent becomes blocked or done. Clicking it opens that agent.
/// Needs the bundled app (`scripts/install.sh`); a bare `swift run` binary has no bundle id,
/// so notifications stay off there.
@MainActor
final class Notifier: NSObject, UNUserNotificationCenterDelegate {
    static let shared = Notifier()
    static let enabledKey = "paca.notifications"

    private weak var store: HerdrStore?

    static var isAvailable: Bool { Bundle.main.bundleIdentifier != nil }

    var enabled: Bool {
        UserDefaults.standard.object(forKey: Self.enabledKey) as? Bool ?? true
    }

    func attach(to store: HerdrStore) {
        self.store = store
        store.onAttention = { [weak self] panes in self?.post(panes) }
        guard Self.isAvailable else { return }
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        center.requestAuthorization(options: [.alert, .sound]) { granted, error in
            debugLog("notifications granted=\(granted) error=\(String(describing: error))")
        }
    }

    private func post(_ panes: [Pane]) {
        guard enabled, Self.isAvailable, let store else { return }
        for pane in panes {
            // Already looking at it: no need to interrupt.
            if NSApp.isActive && store.selectedPaneId == pane.paneId { continue }
            let content = UNMutableNotificationContent()
            content.title = pane.agentStatus == .blocked ? "\(pane.displayName) needs you" : "\(pane.displayName) is done"
            content.body = [pane.kind, store.workspaceTitle(id: pane.workspaceId)].compactMap { $0 }.joined(separator: " · ")
            content.sound = pane.agentStatus == .blocked ? .default : nil
            content.threadIdentifier = pane.paneId
            content.userInfo = ["paneId": pane.paneId, "session": store.sessionName, "machine": store.machine?.id ?? ""]
            if let machine = store.machine { content.subtitle = machine.label }
            // One notification per agent and state: a repeat replaces the old one.
            let id = "\(store.machine?.id ?? "local")/\(store.sessionName)/\(pane.paneId)/\(pane.agentStatus.rawValue)"
            let title = content.title
            UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: id, content: content, trigger: nil)) { error in
                debugLog("notify \(id): \(title)\(error.map { " failed: \($0)" } ?? "")")
            }
        }
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound, .list]
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let info = response.notification.request.content.userInfo
        let paneId = info["paneId"] as? String
        let session = info["session"] as? String
        let machineId = info["machine"] as? String ?? ""
        await MainActor.run {
            guard let store = Notifier.shared.store else { return }
            if !machineId.isEmpty, let machine = store.machines.first(where: { $0.id == machineId }) {
                store.switchMachine(to: machine)
                MainWindow.show(paneId: paneId, store: store)
            } else {
                MainWindow.show(paneId: paneId, session: session, store: store)
            }
        }
    }
}

// MARK: - Global hotkey and floating agent panel

/// ⌥Space anywhere toggles a floating panel with the agent list. It floats over full-screen
/// apps and every Space. Uses Carbon's `RegisterEventHotKey`, which needs no permissions.
@MainActor
final class AgentPanel {
    static let shared = AgentPanel()
    static let enabledKey = "paca.hotkey"

    private var panel: FloatingPanel?
    private var hotKey: EventHotKeyRef?
    private var handler: EventHandlerRef?
    private weak var store: HerdrStore?

    var enabled: Bool {
        UserDefaults.standard.object(forKey: Self.enabledKey) as? Bool ?? true
    }

    func attach(to store: HerdrStore) {
        self.store = store
        setHotKey(enabled)
    }

    /// Registers or removes ⌥Space. Called again when the setting changes.
    func setHotKey(_ on: Bool) {
        if let hotKey { UnregisterEventHotKey(hotKey) }
        hotKey = nil
        guard on else { return }

        if handler == nil {
            var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
            InstallEventHandler(GetApplicationEventTarget(), { _, _, _ in
                DispatchQueue.main.async { MainActor.assumeIsolated { AgentPanel.shared.toggle() } }
                return noErr
            }, 1, &spec, nil, &handler)
        }
        let id = EventHotKeyID(signature: OSType(0x5041_4341), id: 1) // "PACA"
        let status = RegisterEventHotKey(UInt32(kVK_Space), UInt32(optionKey), id, GetApplicationEventTarget(), 0, &hotKey)
        if status != noErr { debugLog("hotkey ⌥Space not registered: \(status)") }
    }

    func toggle() {
        guard let store else { return }
        if let panel, panel.isVisible {
            panel.orderOut(nil)
            return
        }
        let panel = self.panel ?? FloatingPanel(store: store)
        self.panel = panel
        panel.place()
        panel.makeKeyAndOrderFront(nil)
    }

    func hide() { panel?.orderOut(nil) }
}

/// Borderless panel that floats above other windows without stealing focus from them.
private final class FloatingPanel: NSPanel {
    init(store: HerdrStore) {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 340, height: 300),
            styleMask: [.nonactivatingPanel, .titled, .fullSizeContentView],
            backing: .buffered, defer: true
        )
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        standardWindowButton(.closeButton)?.isHidden = true
        standardWindowButton(.miniaturizeButton)?.isHidden = true
        standardWindowButton(.zoomButton)?.isHidden = true
        isMovableByWindowBackground = true
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        let host = NSHostingView(rootView: MenuBarPanel(onOpen: { AgentPanel.shared.hide() }).environment(store))
        host.sizingOptions = [.preferredContentSize]
        contentView = host
    }

    override var canBecomeKey: Bool { true }

    /// Esc closes, like a menu.
    override func cancelOperation(_ sender: Any?) { orderOut(nil) }

    /// Clicking elsewhere closes it too.
    override func resignKey() {
        super.resignKey()
        orderOut(nil)
    }

    /// Top right of the screen under the pointer, just below the menu bar.
    func place() {
        let screen = NSScreen.screens.first { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) } ?? NSScreen.main
        guard let area = screen?.visibleFrame else { return }
        layoutIfNeeded()
        let size = frame.size
        setFrameOrigin(NSPoint(x: area.maxX - size.width - 12, y: area.maxY - size.height - 8))
    }
}

/// Rebuilds its content when the Base16 scheme changes: Theme tokens are plain values,
/// so views pick up new colors by being recreated.
struct Themed<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        content().id(ThemeStore.shared.paletteKey)
    }
}
