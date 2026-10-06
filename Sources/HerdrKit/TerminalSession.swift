import Foundation

/// Live, interactive view of one herdr pane.
///
/// Wraps `herdr terminal session control <pane>`: stdout carries NDJSON
/// `terminal.frame` records (base64 VT bytes) and a final `terminal.closed`;
/// stdin takes NDJSON commands. Shapes verified against herdr 0.9.0:
///
///     {"type":"terminal.input","bytes":"<base64>"}
///     {"type":"terminal.resize","cols":100,"rows":30}
///     {"type":"terminal.scroll","direction":"up","lines":3}
///     {"type":"terminal.release"}
///
/// herdr allows one controller per terminal. Without `takeover`, attaching to
/// a terminal that already has one fails with a `terminal.closed` reason.
public final class TerminalSession: @unchecked Sendable {
    public struct Frame: Sendable {
        public let bytes: Data
        /// True when the frame repaints the whole screen.
        public let full: Bool
        public let cols: Int
        public let rows: Int
    }

    public enum ScrollDirection: String, Sendable { case up, down }

    public let paneId: String
    public var onFrame: (@Sendable (Frame) -> Void)?
    public var onClosed: (@Sendable (_ reason: String?) -> Void)?

    private let process = Process()
    private let stdin = Pipe()
    private let stdout = Pipe()
    private let stderr = Pipe()
    private let writeLock = NSLock()
    private var finished = false
    /// Last size sent to herdr, for repaint requests.
    private var size: (cols: Int, rows: Int)
    /// While paused, frames are dropped before they're even decoded.
    private var paused = false
    private var stats: (delivered: Int, dropped: Int, since: Date) = (0, 0, Date())
    private static let debug = ProcessInfo.processInfo.environment["PACA_DEBUG"] == "1"

    public init(paneId: String, socketPath: String, cols: Int, rows: Int, takeover: Bool = false) {
        self.paneId = paneId
        size = (cols, rows)
        var args: [String] = []
        if let binary = TerminalSession.herdrBinary() {
            process.executableURL = URL(fileURLWithPath: binary)
        } else {
            process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            args.append("herdr")
        }
        args += ["terminal", "session", "control", paneId, "--cols", "\(cols)", "--rows", "\(rows)"]
        if takeover { args.append("--takeover") }
        process.arguments = args

        // Point the child at our socket. Drop pane context inherited from a
        // herdr-managed shell so the child can't resolve the wrong session.
        var env = ProcessInfo.processInfo.environment
        for key in ["HERDR_ENV", "HERDR_PANE_ID", "HERDR_TAB_ID", "HERDR_WORKSPACE_ID", "HERDR_SESSION"] {
            env.removeValue(forKey: key)
        }
        env["HERDR_SOCKET_PATH"] = socketPath
        process.environment = env
        process.standardInput = stdin
        process.standardOutput = stdout
        process.standardError = stderr
    }

    public func start() throws {
        var lineBuffer = Data()
        stdout.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let chunk = handle.availableData
            guard let self, !chunk.isEmpty else { return }
            lineBuffer.append(chunk)
            while let nl = lineBuffer.firstIndex(of: 0x0A) {
                let line = lineBuffer[lineBuffer.startIndex..<nl]
                lineBuffer = Data(lineBuffer[(nl + 1)...])
                self.handle(Data(line))
            }
        }
        process.terminationHandler = { [weak self] _ in
            self?.stdout.fileHandleForReading.readabilityHandler = nil
            self?.finish(reason: nil)
        }
        try process.run()
    }

    public func send(_ bytes: Data) {
        write(["type": "terminal.input", "bytes": bytes.base64EncodedString()])
    }

    public func resize(cols: Int, rows: Int) {
        guard cols > 0, rows > 0 else { return }
        writeLock.withLock { size = (cols, rows) }
        write(["type": "terminal.resize", "cols": cols, "rows": rows])
    }

    /// Hidden tabs pause: herdr keeps the pane attached at its size, but Paca skips decoding,
    /// parsing and drawing its output. Resuming asks for one full repaint: a resize to the
    /// current size returns a full frame without signalling the program (no SIGWINCH).
    public func setPaused(_ requested: Bool) {
        // PACA_NO_PAUSE=1 keeps hidden tabs streaming, for A/B measurements.
        let pause = requested && ProcessInfo.processInfo.environment["PACA_NO_PAUSE"] != "1"
        let (wasPaused, current) = writeLock.withLock { () -> (Bool, (cols: Int, rows: Int)) in
            defer { paused = pause }
            return (paused, size)
        }
        if wasPaused && !pause {
            write(["type": "terminal.resize", "cols": current.cols, "rows": current.rows])
        }
    }

    public func scroll(_ direction: ScrollDirection, lines: Int) {
        write(["type": "terminal.scroll", "direction": direction.rawValue, "lines": lines])
    }

    /// Gives the terminal back to herdr and ends the session.
    public func release() {
        write(["type": "terminal.release"])
        DispatchQueue.global().asyncAfter(deadline: .now() + 1) { [process] in
            if process.isRunning { process.terminate() }
        }
    }

    // MARK: Private

    private func write(_ command: [String: Any]) {
        writeLock.lock()
        defer { writeLock.unlock() }
        guard !finished, process.isRunning,
              var data = try? JSONSerialization.data(withJSONObject: command) else { return }
        data.append(0x0A)
        try? stdin.fileHandleForWriting.write(contentsOf: data)
    }

    private func handle(_ line: Data) {
        // Cheap check before JSON decoding: paused sessions drop frames, never `terminal.closed`.
        if writeLock.withLock({ paused }), line.range(of: Data("terminal.frame".utf8)) != nil {
            stats.dropped += 1
            return
        }
        stats.delivered += 1
        if Self.debug, Date().timeIntervalSince(stats.since) > 2 {
            FileHandle.standardError.write(Data("[paca] \(paneId): \(stats.delivered) frames delivered, \(stats.dropped) dropped in 2s\n".utf8))
            stats = (0, 0, Date())
        }
        guard let object = try? JSONSerialization.jsonObject(with: line) as? [String: Any] else { return }
        switch object["type"] as? String {
        case "terminal.frame":
            guard let b64 = object["bytes"] as? String, let bytes = Data(base64Encoded: b64) else { return }
            onFrame?(Frame(
                bytes: bytes,
                full: object["full"] as? Bool ?? false,
                cols: object["width"] as? Int ?? 0,
                rows: object["height"] as? Int ?? 0
            ))
        case "terminal.closed":
            finish(reason: object["reason"] as? String)
        default:
            break
        }
    }

    private func finish(reason: String?) {
        let shouldNotify: Bool = writeLock.withLock {
            defer { finished = true }
            return !finished
        }
        if shouldNotify { onClosed?(reason) }
    }

    /// herdr's own hint first, then common install locations. Nil means "look it up on PATH".
    static func herdrBinary() -> String? {
        let env = ProcessInfo.processInfo.environment
        if let path = env["HERDR_BIN_PATH"], FileManager.default.isExecutableFile(atPath: path) {
            return path
        }
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let candidates = ["\(home)/.local/bin/herdr", "/opt/homebrew/bin/herdr", "/usr/local/bin/herdr"]
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0) }
    }
}
