import AppKit
import QuartzCore
import HerdrKit
import PacaTheme
import SwiftTerm
import SwiftUI

/// A SwiftTerm view mirroring one herdr pane through `terminal session control`.
/// Typing goes to the pane; the view's size becomes the controller viewport.
struct LiveTerminal: NSViewRepresentable {
    static let metalKey = "terminal.metal"

    /// GPU rendering: about 6× less time per frame than CoreGraphics (0.8 ms vs 4.8 ms measured).
    /// On by default; Settings can turn it off. `PACA_METAL=0/1` overrides for scripted runs.
    static var usesMetal: Bool {
        if let env = ProcessInfo.processInfo.environment["PACA_METAL"] { return env == "1" }
        return UserDefaults.standard.object(forKey: metalKey) as? Bool ?? true
    }

    let paneId: String
    let socketPath: String
    /// Bumping this re-attaches with `--takeover`.
    var takeoverToken: Int = 0
    /// On screen (the tab, or one side of a split). Hidden tabs stay attached.
    var isActive = true
    /// Has the keyboard. Only one visible terminal at a time.
    var isFocused = true
    /// A click in the terminal: the store makes this pane the focused one.
    var onFocus: () -> Void = {}
    /// Ghostty actions that need herdr's scrollback (jump to prompt, scroll to top/bottom).
    var onPaneCommand: (PaneCommand) -> Void = { _ in }
    var onDetached: (String?) -> Void = { _ in }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> TerminalView {
        let view = PacaTerminalView(frame: NSRect(x: 0, y: 0, width: 800, height: 500))
        view.isVisibleTab = isActive
        view.wantsFocus = isFocused
        view.onClickFocus = onFocus
        view.font = ThemeStore.shared.terminalFont
        view.terminalDelegate = context.coordinator
        view.onLayout = { [weak coordinator = context.coordinator] in coordinator?.startIfReady() }
        if Self.usesMetal {
            do { try view.setUseMetal(true) } catch { debugLog("metal unavailable: \(error)") }
        }
        context.coordinator.view = view
        context.coordinator.onDetached = onDetached
        context.coordinator.isActive = isActive
        context.coordinator.isFocused = isFocused
        context.coordinator.onPaneCommand = onPaneCommand
        context.coordinator.attach(paneId: paneId, socketPath: socketPath, takeover: false)
        return view
    }

    func updateNSView(_ view: TerminalView, context: Context) {
        let c = context.coordinator
        c.onDetached = onDetached
        c.isActive = isActive
        c.isFocused = isFocused
        c.onPaneCommand = onPaneCommand
        if let view = view as? PacaTerminalView {
            view.isVisibleTab = isActive
            view.wantsFocus = isFocused
            view.onClickFocus = onFocus
        }
        if c.paneId != paneId {
            c.attach(paneId: paneId, socketPath: socketPath, takeover: false)
        } else if c.takeoverToken != takeoverToken {
            c.takeoverToken = takeoverToken
            c.attach(paneId: paneId, socketPath: socketPath, takeover: true)
        }
    }

    static func dismantleNSView(_ view: TerminalView, coordinator: Coordinator) {
        coordinator.detach()
    }

    final class Coordinator: NSObject, TerminalViewDelegate, @unchecked Sendable {
        weak var view: TerminalView?
        var onDetached: (String?) -> Void = { _ in }
        private(set) var paneId: String?
        var takeoverToken = 0
        private var session: TerminalSession?
        private var pending: (paneId: String, socketPath: String, takeover: Bool)?
        private var resizeWork: DispatchWorkItem?
        private var scrollMonitor: Any?
        private var keyMonitor: Any?
        private var pacer: FramePacer?
        var isFocused = true {
            didSet { pacer?.focused = isFocused }
        }
        /// Only the visible tab scrolls and draws; hidden tabs pause their stream.
        var isActive = true {
            didSet { if isActive != oldValue { session?.setPaused(!isActive) } }
        }
        /// Scroll lines waiting to be sent; flushed once per display frame.
        private var pendingScroll = 0
        private var scrollFlushScheduled = false
        private var scrollRemainder: CGFloat = 0

        /// Attaching sets the pane's real size, and every size change makes TUIs like Claude Code
        /// redraw (often leaving junk behind). So wait until the view has its final size, then
        /// attach once at that size.
        func attach(paneId: String, socketPath: String, takeover: Bool) {
            detach()
            self.paneId = paneId
            pending = (paneId, socketPath, takeover)
            startIfReady()
        }

        func startIfReady() {
            guard let request = pending, let view, view.window != nil,
                  view.bounds.width > 120, view.bounds.height > 80 else { return }
            pending = nil
            start(paneId: request.paneId, socketPath: request.socketPath, takeover: request.takeover, in: view)
        }

        private func start(paneId: String, socketPath: String, takeover: Bool, in view: TerminalView) {
            debugLog("attach \(paneId) takeover=\(takeover) view=\(Int(view.bounds.width))x\(Int(view.bounds.height)) font=\(view.font.fontName) \(view.font.pointSize)")
            applyColors(view)

            let terminal = view.getTerminal()
            debugLog("attach size \(max(terminal.cols, 20))x\(max(terminal.rows, 5))")
            let session = TerminalSession(
                paneId: paneId, socketPath: socketPath,
                cols: max(terminal.cols, 20), rows: max(terminal.rows, 5), takeover: takeover
            )
            let pacer = FramePacer()
            pacer.focused = isFocused
            self.pacer = pacer
            session.onFrame = { [weak self, weak view] frame in
                pacer.add(frame.bytes) { bytes, arrived in
                    let start = CACurrentMediaTime()
                    view?.feed(byteArray: ArraySlice(bytes))
                    // Timing only in debug runs: forcing a draw per frame would defeat coalescing.
                    if debugEnabled, let sent = self?.lastInputAt {
                        view?.displayIfNeeded()
                        self?.lastInputAt = nil
                        debugLog(String(format: "latency key→frame %.1fms, main-queue wait %.1fms, feed+draw %.1fms (%d bytes)",
                                        (arrived - sent) * 1000, (start - arrived) * 1000, (CACurrentMediaTime() - start) * 1000, bytes.count))
                    }
                }
            }
            session.onClosed = { [weak self, weak session] reason in
                debugLog("closed \(reason ?? "-")")
                DispatchQueue.main.async {
                    guard let self, self.session === session else { return }
                    self.onDetached(reason)
                }
            }
            self.session = session
            if !isActive { session.setPaused(true) }
            installScrollMonitor()
            do {
                try session.start()
            } catch {
                onDetached("could not launch herdr: \(error)")
            }
        }

        /// Background, foreground and the 16 ANSI colors all come from the Base16 scheme,
        /// so agent output uses the same palette as the rest of Paca.
        private func applyColors(_ view: TerminalView) {
            let palette = Theme.palette
            view.nativeBackgroundColor = Theme.ns(palette.terminalBackground)
            view.nativeForegroundColor = Theme.ns(palette.terminalForeground)
            view.caretColor = Theme.ns(palette.caret)
            view.selectedTextBackgroundColor = Theme.ns(palette.terminalSelection)
            // SwiftTerm defaults selected text to black. ThemePalette checks the selection
            // against the terminal foreground, so draw selected text in that color.
            view.selectedTextForegroundColor = Theme.ns(palette.terminalForeground)
            view.installColors(palette.ansi.map { c in
                SwiftTerm.Color(red: UInt16(c.r * 65535), green: UInt16(c.g * 65535), blue: UInt16(c.b * 65535))
            })
        }

        func detach() {
            if let scrollMonitor { NSEvent.removeMonitor(scrollMonitor) }
            if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
            scrollMonitor = nil
            keyMonitor = nil
            pending = nil
            resizeWork?.cancel()
            session?.release()
            session = nil
        }

        // MARK: TerminalViewDelegate

        /// Paca only receives the visible screen, so history lives in herdr. Wheel and trackpad
        /// scrolling over this terminal scroll herdr's scrollback instead of SwiftTerm's empty
        /// local buffer. Apps that track the mouse (vim with mouse on, htop) still get the wheel.
        /// Ghostty `keybind = trigger=text:…` entries (like shift+enter → newline) apply here too,
        /// checked before SwiftTerm sees the key.
        var onPaneCommand: (PaneCommand) -> Void = { _ in }

        private func installKeyMonitor() {
            guard keyMonitor == nil else { return }
            keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard let self, let view = self.view, self.session != nil, self.isActive,
                      event.window === view.window, view.window?.firstResponder === view else { return event }
                return self.handleKey(event, in: view) ? nil : event
            }
        }

        /// Ghostty keybinds first (your config, or Ghostty's defaults), checked before SwiftTerm
        /// sees the key. True when the key was handled.
        func handleKey(_ event: NSEvent, in view: TerminalView) -> Bool {
            guard let trigger = KeyTrigger(event: event),
                  let action = MainActor.assumeIsolated({ ThemeStore.shared.ghosttyKeybinds[trigger] }) else { return false }
            switch action {
            case .text(let bytes): view.send(data: bytes[...])
            case .jumpToPrompt(let step): onPaneCommand(.jumpToPrompt(step))
            case .scrollToTop: onPaneCommand(.scrollToTop)
            case .scrollToBottom: onPaneCommand(.scrollToBottom)
            case .scrollPageUp: session?.scroll(.up, lines: max(view.getTerminal().rows - 1, 1))
            case .scrollPageDown: session?.scroll(.down, lines: max(view.getTerminal().rows - 1, 1))
            }
            return true
        }

        private func installScrollMonitor() {
            installKeyMonitor()
            guard scrollMonitor == nil else { return }
            scrollMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
                guard let self, let view = self.view, self.session != nil,
                      self.isActive, event.window === view.window,
                      view.bounds.contains(view.convert(event.locationInWindow, from: nil)),
                      view.getTerminal().mouseMode == .off else { return event }
                self.scroll(by: event, in: view)
                return nil
            }
        }

        func scroll(by event: NSEvent, in view: TerminalView) {
            let terminal = view.getTerminal()
            let cellHeight = max(view.bounds.height / CGFloat(max(terminal.rows, 1)), 1)
            let lines: Int
            if event.hasPreciseScrollingDeltas {
                scrollRemainder += event.scrollingDeltaY
                lines = Int(scrollRemainder / cellHeight)
                scrollRemainder -= CGFloat(lines) * cellHeight
            } else {
                scrollRemainder = 0
                lines = event.scrollingDeltaY == 0 ? 0 : (event.scrollingDeltaY > 0 ? max(1, Int(event.scrollingDeltaY.rounded())) : min(-1, Int(event.scrollingDeltaY.rounded())))
            }
            guard lines != 0 else { return }
            // A trackpad sends 100+ events a second; send one command per display frame so
            // herdr returns one frame to draw instead of one per event.
            pendingScroll += lines
            guard !scrollFlushScheduled else { return }
            scrollFlushScheduled = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0 / 120) { [weak self] in
                guard let self else { return }
                self.scrollFlushScheduled = false
                let total = self.pendingScroll
                self.pendingScroll = 0
                guard total != 0 else { return }
                debugLog("scroll \(total > 0 ? "up" : "down") \(abs(total))")
                self.pacer?.noteUserInput()
                self.session?.scroll(total > 0 ? .up : .down, lines: abs(total))
            }
        }

        /// Sidebar animations and drags change the size many times a second; only the
        /// settled size reaches the pane, so the program inside redraws once.
        func sizeChanged(source: TerminalView, newCols: Int, newRows: Int) {
            guard let session else { startIfReady(); return }
            resizeWork?.cancel()
            let work = DispatchWorkItem { [weak session] in
                debugLog("resize \(newCols)x\(newRows)")
                session?.resize(cols: newCols, rows: newRows)
            }
            resizeWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: work)
        }

        /// Debug timing (PACA_DEBUG=1): when the last keystroke left, to time the echo frame.
        var lastInputAt: CFTimeInterval?

        func send(source: TerminalView, data: ArraySlice<UInt8>) {
            lastInputAt = CACurrentMediaTime()
            pacer?.noteUserInput()
            session?.send(Data(data))
        }

        func setTerminalTitle(source: TerminalView, title: String) {}
        func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {}
        func scrolled(source: TerminalView, position: Double) {}
        func rangeChanged(source: TerminalView, startY: Int, endY: Int) {}
    }
}

/// SwiftTerm passes ⌘-keys to the text system, which drops the line-editing commands.
/// This maps them to the bytes macOS terminals send (Terminal.app, iTerm2, Ghostty),
/// which shells, readline and agent prompts like Claude Code understand.
final class PacaTerminalView: TerminalView {
    /// Called when the view joins a window or changes size, so attaching can wait for a real size.
    var onLayout: (() -> Void)?

    /// Background tabs stay attached but are hidden at the AppKit level: SwiftUI opacity alone
    /// still lets them receive clicks and keyboard focus.
    var isVisibleTab = true {
        didSet {
            guard isVisibleTab != oldValue else { return }
            isHidden = !isVisibleTab
            if isVisibleTab { focusSoon() } else if window?.firstResponder === self { window?.makeFirstResponder(nil) }
        }
    }

    /// The focused terminal takes the keyboard as soon as it can, so typing works first try.
    var wantsFocus = true {
        didSet { if wantsFocus && !oldValue { focusSoon() } }
    }

    var onClickFocus: (() -> Void)?

    func focusSoon() {
        DispatchQueue.main.async { [weak self] in
            guard let self, self.isVisibleTab, self.wantsFocus,
                  let window = self.window, window.firstResponder !== self else { return }
            window.makeFirstResponder(self)
        }
    }

    /// SwiftTerm starts a selection on click but never takes focus.
    override func mouseDown(with event: NSEvent) {
        if window?.firstResponder !== self { window?.makeFirstResponder(self) }
        onClickFocus?()
        super.mouseDown(with: event)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window != nil { focusSoon() }
        onLayout?()
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        onLayout?()
    }

    /// ⌘-key → bytes. Key codes are layout-independent (arrows, delete).
    static let commandKeys: [UInt16: [UInt8]] = [
        123: [0x01],  // ⌘←  start of line (Ctrl-A)
        124: [0x05],  // ⌘→  end of line (Ctrl-E)
        51: [0x15],   // ⌘⌫  delete to start of line (Ctrl-U)
        117: [0x0B],  // ⌘⌦  delete to end of line (Ctrl-K)
    ]

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard window?.firstResponder === self else { return super.performKeyEquivalent(with: event) }
        let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask).subtracting([.numericPad, .function, .capsLock])
        if mods == .command, let bytes = Self.commandKeys[event.keyCode] {
            send(data: bytes[...])
            return true
        }
        // ⌘ + arrow with no binding (⌘⇧←, ⌘⌥→ …): send it on like Ghostty's legacy encoding,
        // CSI 1;{1 + shift + 2·alt + 4·ctrl + 8·super}{A–D}. Programs that enabled the kitty
        // keyboard protocol get SwiftTerm's own encoding instead.
        if mods.contains(.command), getTerminal().keyboardEnhancementFlags.isEmpty,
           let final = Self.arrowFinals[event.keyCode] {
            var modifier = 1 + 8
            if mods.contains(.shift) { modifier += 1 }
            if mods.contains(.option) { modifier += 2 }
            if mods.contains(.control) { modifier += 4 }
            send(data: Array("\u{1b}[1;\(modifier)\(final)".utf8)[...])
            return true
        }
        return super.performKeyEquivalent(with: event)
    }

    static let arrowFinals: [UInt16: Character] = [126: "A", 125: "B", 124: "C", 123: "D"]
}

/// A key plus modifiers in Ghostty's vocabulary (`super+backspace`, `shift+enter`).
struct KeyTrigger: Hashable {
    let mods: Set<String>
    let key: String

    private static let modAliases = ["cmd": "super", "command": "super", "super": "super",
                                     "opt": "alt", "option": "alt", "alt": "alt",
                                     "ctrl": "ctrl", "control": "ctrl", "shift": "shift"]
    private static let keyAliases = ["return": "enter", "arrow_left": "left", "arrow_right": "right",
                                     "arrow_up": "up", "arrow_down": "down", "esc": "escape"]
    private static let keyCodes: [UInt16: String] = [36: "enter", 76: "enter", 48: "tab", 51: "backspace", 117: "delete",
                                                     53: "escape", 49: "space", 123: "left", 124: "right", 125: "down", 126: "up",
                                                     115: "home", 119: "end", 116: "page_up", 121: "page_down"]

    /// Parses a Ghostty trigger. Sequences (`a>b`) and `physical:` keys aren't supported.
    init?(ghostty trigger: String) {
        guard !trigger.contains(">"), !trigger.contains(":") else { return nil }
        var parts = trigger.lowercased().split(separator: "+").map(String.init)
        guard let last = parts.popLast() else { return nil }
        var mods = Set<String>()
        for part in parts {
            guard let mod = Self.modAliases[part] else { return nil }
            mods.insert(mod)
        }
        self.mods = mods
        key = Self.keyAliases[last] ?? last
    }

    init?(event: NSEvent) {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        var mods = Set<String>()
        if flags.contains(.command) { mods.insert("super") }
        if flags.contains(.option) { mods.insert("alt") }
        if flags.contains(.control) { mods.insert("ctrl") }
        if flags.contains(.shift) { mods.insert("shift") }
        if let named = Self.keyCodes[event.keyCode] {
            key = named
        } else if let chars = event.charactersIgnoringModifiers?.lowercased(), chars.count == 1 {
            key = chars
        } else {
            return nil
        }
        self.mods = mods
    }
}

/// Batches herdr frames so a streaming pane redraws at most ~30 times a second.
/// SwiftTerm needs ~13 ms for a full 150x48 redraw; at herdr's ~55 frames/s that alone
/// saturates the main thread and keystrokes queue behind it. After a quiet period the next
/// frame goes straight through, so typing echo stays immediate.
final class FramePacer: @unchecked Sendable {
    /// 30 fps for the pane you're typing in, 15 fps for a visible pane you're not (the other side
    /// of a split), so a streaming neighbour can't crowd out your keystrokes.
    var focused = true
    /// Frames right after a keystroke or scroll skip pacing, so anything you drive draws at
    /// full speed (up to herdr's ~60 fps); only output you're just watching is capped.
    private var typingUntil: CFTimeInterval = 0

    func noteUserInput() {
        lock.withLock { typingUntil = CACurrentMediaTime() + 0.25 }
    }

    private static let override = ProcessInfo.processInfo.environment["PACA_FRAME_MS"].flatMap(Double.init).map { $0 / 1000 }

    private var interval: CFTimeInterval {
        Self.override ?? (focused ? 1.0 / 30 : 1.0 / 15)
    }

    private let lock = NSLock()
    private var pending = Data()
    private var firstArrival: CFTimeInterval = 0
    private var scheduled = false
    private var lastFlush: CFTimeInterval = 0

    /// Called on herdr's reader thread. `deliver` runs on the main thread with every byte
    /// received since the last delivery, in order.
    func add(_ bytes: Data, deliver: @escaping @Sendable (Data, CFTimeInterval) -> Void) {
        let now = CACurrentMediaTime()
        let delay: CFTimeInterval? = lock.withLock {
            if pending.isEmpty { firstArrival = now }
            pending.append(bytes)
            guard !scheduled else { return nil }
            scheduled = true
            return now < typingUntil ? 0 : max(0, lastFlush + interval - now)
        }
        guard let delay else { return }
        let flush = { [self] in
            let (batch, arrived) = lock.withLock { () -> (Data, CFTimeInterval) in
                defer { pending = Data(); scheduled = false; lastFlush = CACurrentMediaTime() }
                return (pending, firstArrival)
            }
            if !batch.isEmpty { deliver(batch, arrived) }
        }
        if delay == 0 { DispatchQueue.main.async(execute: flush) } else { DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: flush) }
    }
}

/// Terminal actions that go through herdr rather than bytes to the program.
enum PaneCommand {
    case jumpToPrompt(Int)
    case scrollToTop
    case scrollToBottom
}

