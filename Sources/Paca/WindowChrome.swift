import AppKit
import SwiftTerm
import SwiftUI

/// Makes the window draw edge to edge under a transparent unified title bar
/// (traffic lights centered like Codex/Slack) and reports the bar's height.
struct WindowChrome: NSViewRepresentable {
    @Binding var titlebarHeight: CGFloat

    func makeNSView(context: Context) -> ProbeView {
        let view = ProbeView()
        view.onWindow = { window in
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            window.styleMask.insert(.fullSizeContentView)
            // No NSToolbar: its view sits over the title strip and swallows clicks meant
            // for Paca's own title-bar controls.
            window.toolbar = nil
            DispatchQueue.main.async {
                titlebarHeight = window.frame.height - window.contentLayoutRect.height
                WindowChrome.centerTrafficLights(in: window)
            }
            // AppKit puts the buttons back on resize and full-screen changes.
            for name in [NSWindow.didResizeNotification, NSWindow.didExitFullScreenNotification, NSWindow.didBecomeKeyNotification] {
                view.observers.append(NotificationCenter.default.addObserver(forName: name, object: window, queue: .main) { _ in
                    WindowChrome.centerTrafficLights(in: window)
                })
            }
        }
        return view
    }

    func updateNSView(_ view: ProbeView, context: Context) {
        guard let window = view.window else {
            DispatchQueue.main.async { view.window.map(apply) }
            return
        }
        apply(to: window)
    }

    /// Opaque window in the theme's chrome color, so resizing never flashes another color.
    private func apply(to window: NSWindow) {
        window.isOpaque = true
        window.backgroundColor = Theme.chromeNS
    }

    /// Centers the close/minimize/zoom buttons in Paca's taller top bar (Codex/Slack style).
    static func centerTrafficLights(in window: NSWindow, barHeight: CGFloat = TopBar.height) {
        guard !window.styleMask.contains(.fullScreen) else { return }
        let buttons = [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton].compactMap(window.standardWindowButton)
        guard let titlebar = buttons.first?.superview else { return }
        for (index, button) in buttons.enumerated() {
            let size = button.frame.size
            // Same gap from the left edge as from the top, so the corner reads as even.
            let inset = (barHeight - size.height) / 2
            let y = titlebar.isFlipped ? inset : titlebar.bounds.height - inset - size.height
            button.setFrameOrigin(NSPoint(x: inset + CGFloat(index) * 20, y: y))
        }
    }

    final class ProbeView: NSView {
        var observers: [NSObjectProtocol] = []
        deinit { observers.forEach(NotificationCenter.default.removeObserver) }
        var onWindow: ((NSWindow) -> Void)?
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let window { onWindow?(window) }
        }
    }
}

/// `--snapshot PATH`: draw the main window (title bar included) into a PNG and quit.
/// Works without Screen Recording permission because the app renders itself.
enum WindowSnapshot {
    /// `--keys "text:echo hi,cmd+backspace,return"`: real key events through NSApp, after `--click`
    /// has focused a view. Lets scripted checks prove terminal keybindings end to end.
    static func sendKeys(_ spec: String, to window: NSWindow) {
        let named: [String: (UInt16, String)] = [
            "left": (123, "\u{F702}"), "right": (124, "\u{F703}"), "up": (126, "\u{F700}"), "down": (125, "\u{F701}"),
            "backspace": (51, "\u{7F}"), "delete": (117, "\u{F728}"), "return": (36, "\r"),
            "home": (115, "\u{F729}"), "end": (119, "\u{F72B}"),
        ]
        // A background-launched app has no key window; focus the clicked view explicitly.
        // Make the window key but leave focus to Paca, so the test catches focus bugs.
        window.makeKeyAndOrderFront(nil)
        debugLog("first responder: \(describe(window.firstResponder))")
        var delay = 0.2
        for token in spec.split(separator: ",").map(String.init) {
            var events: [(UInt16, String, NSEvent.ModifierFlags)] = []
            if token.hasPrefix("text:") {
                events = token.dropFirst(5).map { (0, String($0), []) }
            } else {
                let parts = token.split(separator: "+").map(String.init)
                var flags: NSEvent.ModifierFlags = []
                if parts.contains("cmd") { flags.insert(.command) }
                if parts.contains("opt") { flags.insert(.option) }
                if parts.contains("ctrl") { flags.insert(.control) }
                if parts.contains("shift") { flags.insert(.shift) }
                guard let last = parts.last,
                      let key = named[last] ?? (last.count == 1 ? (ansiKeyCodes[last] ?? 0, parts.contains("shift") ? last.uppercased() : last) : nil) else { continue }
                if [123, 124, 125, 126].contains(key.0) { flags.formUnion([.numericPad, .function]) }
                if [117, 115, 119].contains(key.0) { flags.insert(.function) }
                events = [(key.0, key.1, flags)]
            }
            for (code, chars, flags) in events {
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                    guard let event = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: flags,
                                                       timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
                                                       context: nil, characters: chars, charactersIgnoringModifiers: chars,
                                                       isARepeat: false, keyCode: code) else { return }
                    // Same order as a real keypress. Local monitors run first (they see events in
                    // nextEvent, which sendEvent skips): app shortcuts, then Ghostty keybinds.
                    if AppShortcuts.handle(event) { return }
                    if let terminal = window.firstResponder as? TerminalView,
                       let coordinator = terminal.terminalDelegate as? LiveTerminal.Coordinator,
                       coordinator.handleKey(event, in: terminal) {
                        return
                    }
                    // Then NSApplication's key-equivalent pass (menu, then views), then keyDown.
                    if flags.contains(.command),
                       NSApp.mainMenu?.performKeyEquivalent(with: event) == true || window.performKeyEquivalent(with: event) {
                        return
                    }
                    window.sendEvent(event)
                }
                delay += 0.03
            }
            delay += 0.15
        }
        debugLog("keys \(spec)")
    }

    /// US-layout key codes, so synthesized shortcuts match like real key presses.
    static let ansiKeyCodes: [String: UInt16] = [
        "a": 0, "s": 1, "d": 2, "f": 3, "h": 4, "g": 5, "z": 6, "x": 7, "c": 8, "v": 9, "b": 11, "q": 12,
        "w": 13, "e": 14, "r": 15, "y": 16, "t": 17, "1": 18, "2": 19, "3": 20, "4": 21, "6": 22, "5": 23,
        "9": 25, "7": 26, "8": 28, "0": 29, "o": 31, "u": 32, "i": 34, "p": 35, "l": 37, "j": 38, "k": 40,
        "n": 45, "m": 46,
    ]

    static func describe(_ responder: NSResponder?) -> String {
        guard let responder else { return "nil" }
        if let terminal = responder as? PacaTerminalView,
           let coordinator = terminal.terminalDelegate as? LiveTerminal.Coordinator {
            return "terminal \(coordinator.paneId ?? "?") visible=\(terminal.isVisibleTab)"
        }
        return String(describing: type(of: responder))
    }

    private static func firstTerminal(in view: NSView) -> NSView? {
        if view is PacaTerminalView { return view }
        for sub in view.subviews { if let hit = firstTerminal(in: sub) { return hit } }
        return nil
    }

    static func scheduleIfRequested() {
        if let text = PacaApp.argument("--tip") {
            let delay = Double(PacaApp.argument("--snapshot-delay") ?? "") ?? 3
            DispatchQueue.main.asyncAfter(deadline: .now() + delay - 0.6) { HoverTipCenter.shared.showRegistered(text) }
        }
        // `--window-size WxH`: scripted runs at a realistic size.
        if let spec = PacaApp.argument("--window-size") {
            let parts = spec.split(separator: "x").compactMap { Double($0) }
            DispatchQueue.main.async {
                if parts.count == 2, let window = NSApp.windows.first(where: { $0.isVisible && $0.frame.width > 400 }) {
                    window.setContentSize(NSSize(width: parts[0], height: parts[1]))
                }
            }
        }
        guard let path = PacaApp.argument("--snapshot") else { return }
        let delay = Double(PacaApp.argument("--snapshot-delay") ?? "") ?? 3
        // `--click X,Y` (points from the window's top-left): send a real click through
        // AppKit first, so scripted checks can prove title-bar controls respond.
        if let spec = PacaApp.argument("--click") {
            let parts = spec.split(separator: ",").compactMap { Double($0) }
            // Leave time for --keys to finish before the snapshot.
            let clickAt = PacaApp.argument("--keys") == nil ? delay - 1 : max(1, delay - 4)
            DispatchQueue.main.asyncAfter(deadline: .now() + clickAt) {
                guard parts.count == 2, let window = NSApp.windows.first(where: { $0.isVisible && $0.frame.width > 400 }) else { return }
                let point = NSPoint(x: parts[0], y: window.frame.height - parts[1])
                for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
                    if let event = NSEvent.mouseEvent(with: type, location: point, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                                                      windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1) {
                        window.sendEvent(event)
                    }
                }
                debugLog("clicked \(spec)")
                if let keys = PacaApp.argument("--keys") { sendKeys(keys, to: window) }
                // `--scroll N` (lines, positive = back in history) posts a real wheel event at the
                // click point into Paca's own event queue, so it passes through event monitors.
                if let lines = PacaApp.argument("--scroll").flatMap(Int32.init) {
                    let screenPoint = window.convertPoint(toScreen: point)
                    let flipped = CGPoint(x: screenPoint.x, y: (NSScreen.screens.first?.frame.height ?? 0) - screenPoint.y)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        if let wheel = CGEvent(scrollWheelEvent2Source: nil, units: .line, wheelCount: 1, wheel1: lines, wheel2: 0, wheel3: 0) {
                            wheel.location = flipped
                            guard let event = NSEvent(cgEvent: wheel) else { return }
                            // Local monitors only see events from the window server; hand this one
                            // straight to the terminal's handler, the same code the monitor calls.
                            if let terminal = window.contentView.flatMap(firstTerminal(in:)) as? TerminalView,
                               let coordinator = terminal.terminalDelegate as? LiveTerminal.Coordinator {
                                coordinator.scroll(by: event, in: terminal)
                            }
                            debugLog("sent scroll \(lines)")
                        }
                    }
                }
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            defer { NSApp.terminate(nil) }
            debugLog("visible windows: \(NSApp.windows.filter(\.isVisible).map { $0.title.isEmpty ? $0.identifier?.rawValue ?? "?" : $0.title })")
            guard let window = NSApp.windows.first(where: { $0.identifier?.rawValue.contains("main") == true && $0.isVisible })
                    ?? NSApp.windows.first(where: { $0.isVisible && $0.contentView != nil && $0.frame.width > 400 }),
                  let frameView = window.contentView?.superview else {
                FileHandle.standardError.write(Data("[paca] snapshot: no window\n".utf8))
                return
            }
            // Render the layer tree, not draw(_:), so layer-backed views (SwiftTerm) keep their backgrounds.
            frameView.wantsLayer = true
            let scale = window.backingScaleFactor
            let size = frameView.bounds.size
            guard let layer = frameView.layer,
                  let rep = NSBitmapImageRep(
                    bitmapDataPlanes: nil, pixelsWide: Int(size.width * scale), pixelsHigh: Int(size.height * scale),
                    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                    colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
                  let context = NSGraphicsContext(bitmapImageRep: rep) else { return }
            let cg = context.cgContext
            cg.scaleBy(x: scale, y: scale)
            if !layer.isGeometryFlipped && frameView.isFlipped {
                cg.translateBy(x: 0, y: size.height)
                cg.scaleBy(x: 1, y: -1)
            }
            layer.render(in: cg)
            context.flushGraphics()

            // SwiftTerm leaves default-background cells transparent and lets its layer color
            // show through, which render(in:) skips. Flatten onto the terminal color so the
            // PNG matches the screen.
            guard let layered = rep.cgImage,
                  let flat = NSBitmapImageRep(
                    bitmapDataPlanes: nil, pixelsWide: rep.pixelsWide, pixelsHigh: rep.pixelsHigh,
                    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                    colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
                  let flatContext = NSGraphicsContext(bitmapImageRep: flat) else { return }
            let bounds = CGRect(x: 0, y: 0, width: rep.pixelsWide, height: rep.pixelsHigh)
            flatContext.cgContext.setFillColor(Theme.ns(Theme.palette.terminalBackground).cgColor)
            flatContext.cgContext.fill(bounds)
            flatContext.cgContext.draw(layered, in: bounds)
            flatContext.flushGraphics()
            let output = flat
            let url = URL(fileURLWithPath: path)
            try? output.representation(using: .png, properties: [:])?.write(to: url)
            FileHandle.standardError.write(Data("[paca] snapshot written to \(url.path)\n".utf8))
        }
    }
}
