import Foundation

/// Request/response client for the herdr socket API (newline-delimited JSON).
/// herdr answers one request per connection and then closes it, so every call
/// opens its own short-lived socket. Subscriptions use `HerdrClient.events(...)`.
public final class HerdrClient: @unchecked Sendable {
    public let socketPath: String

    private let lock = NSLock()
    private var nextId = 0

    public init(socketPath: String = HerdrClient.defaultSocketPath()) {
        self.socketPath = socketPath
    }

    /// Nothing stays open between calls. Kept so callers can drop a client explicitly.
    public func close() {}

    /// Socket for a named session, or the default session when `session` is nil.
    /// Mirrors herdr's own resolution: explicit session, then HERDR_SOCKET_PATH, then default.
    public static func defaultSocketPath(session: String? = nil) -> String {
        let base = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/herdr").path
        if let session, session != "default" {
            return "\(base)/sessions/\(session)/herdr.sock"
        }
        if let env = ProcessInfo.processInfo.environment["HERDR_SOCKET_PATH"], !env.isEmpty {
            return env
        }
        return "\(base)/herdr.sock"
    }

    // MARK: Requests

    /// Sends `method` on a fresh connection and returns the raw `result` object as JSON data.
    public func call(_ method: String, params: [String: Any] = [:]) async throws -> Data {
        let id: String = lock.withLock {
            nextId += 1
            return "paca_\(nextId)"
        }
        let body: [String: Any] = ["id": id, "method": method, "params": params]
        let request = try JSONSerialization.data(withJSONObject: body)
        let socket = try LineSocket(path: socketPath)
        let once = Once()

        let reply: Data = try await withCheckedThrowingContinuation { cont in
            socket.startReading(
                onLine: { line in
                    if once.claim() { cont.resume(returning: line) }
                    socket.close()
                },
                onClose: {
                    if once.claim() { cont.resume(throwing: HerdrError.disconnected) }
                }
            )
            do {
                try socket.send(request)
            } catch {
                if once.claim() { cont.resume(throwing: error) }
                socket.close()
            }
        }
        return try Self.result(of: reply, method: method)
    }

    /// Sends `method` and decodes `result.<key>` as `T`.
    public func call<T: Decodable>(_ method: String, params: [String: Any] = [:], key: String, as type: T.Type) async throws -> T {
        let data = try await call(method, params: params)
        let object = try JSONSerialization.jsonObject(with: data)
        guard let dict = object as? [String: Any], let value = dict[key] else {
            throw HerdrError.decoding("\(method): missing result.\(key)")
        }
        let inner = try JSONSerialization.data(withJSONObject: value)
        do {
            return try HerdrJSON.decoder.decode(T.self, from: inner)
        } catch {
            throw HerdrError.decoding("\(method): \(error)")
        }
    }

    public func ping() async throws -> Data {
        try await call("ping")
    }

    public func snapshot() async throws -> SessionSnapshot {
        try await call("session.snapshot", key: "snapshot", as: SessionSnapshot.self)
    }

    public func prompt(agent target: String, text: String) async throws {
        _ = try await call("agent.prompt", params: ["target": target, "text": text])
    }

    /// Recent output of a pane as plain text (ANSI stripped, wrapped lines joined).
    public func recentOutput(of paneId: String, lines: Int) async throws -> String {
        struct Read: Decodable { let text: String }
        return try await call(
            "pane.read",
            params: ["pane_id": paneId, "source": "recent_unwrapped", "lines": lines, "strip_ansi": true, "format": "text"],
            key: "read", as: Read.self
        ).text
    }

    // MARK: Workspaces

    /// Creates a workspace rooted at `cwd` without moving focus in the herdr TUI.
    @discardableResult
    public func createWorkspace(cwd: String, label: String?) async throws -> Workspace {
        var params: [String: Any] = ["cwd": cwd, "focus": false]
        if let label { params["label"] = label }
        return try await call("workspace.create", params: params, key: "workspace", as: Workspace.self)
    }

    public func renameWorkspace(_ workspaceId: String, label: String) async throws {
        _ = try await call("workspace.rename", params: ["workspace_id": workspaceId, "label": label])
    }

    /// Closes the workspace and every pane in it. Agents running there are killed.
    public func closeWorkspace(_ workspaceId: String) async throws {
        _ = try await call("workspace.close", params: ["workspace_id": workspaceId])
    }

    /// Moves the workspace so it ends up at `index` (0-based) in the list.
    public func moveWorkspace(_ workspaceId: String, to index: Int) async throws {
        _ = try await call("workspace.move", params: ["workspace_id": workspaceId, "insert_index": index])
    }

    // MARK: Panes and agents

    public enum SplitDirection: String, Sendable { case right, down }

    /// Opens a new tab in the workspace with one shell pane, and returns that pane.
    public func newTab(in workspaceId: String) async throws -> Pane {
        try await call("tab.create", params: ["workspace_id": workspaceId, "focus": false], key: "root_pane", as: Pane.self)
    }

    /// Splits `paneId` and returns the new shell pane.
    public func splitPane(_ paneId: String, direction: SplitDirection) async throws -> Pane {
        try await call(
            "pane.split",
            params: ["target_pane_id": paneId, "direction": direction.rawValue, "focus": false],
            key: "pane", as: Pane.self
        )
    }

    /// Launches agent `kind` in a pane sitting at a shell prompt. herdr replies at once
    /// with `launch_pending`; the agent shows up in later snapshots as it starts.
    /// A brand-new pane's shell may still be loading its rc files, which herdr reports as
    /// `agent_pane_busy`, so that error is retried until `shellTimeout` runs out.
    public func startAgent(kind: String, name: String, in paneId: String, shellTimeout: Duration = .seconds(10)) async throws {
        let deadline = ContinuousClock.now + shellTimeout
        while true {
            do {
                _ = try await call("agent.start", params: ["pane_id": paneId, "kind": kind, "name": name])
                return
            } catch HerdrError.server(code: "agent_pane_busy", _) where ContinuousClock.now < deadline {
                try await Task.sleep(for: .milliseconds(250))
            }
        }
    }

    public func renameAgent(in paneId: String, to name: String) async throws {
        _ = try await call("agent.rename", params: ["target": paneId, "name": name])
    }

    public func renamePane(_ paneId: String, label: String) async throws {
        _ = try await call("pane.rename", params: ["pane_id": paneId, "label": label])
    }

    /// Closes the pane and kills whatever runs in it. A tab closes with its last pane.
    public func closePane(_ paneId: String) async throws {
        _ = try await call("pane.close", params: ["pane_id": paneId])
    }

    /// Focuses the pane in the herdr TUI. For agents this also marks `done` as seen.
    public func focusPane(_ paneId: String, isAgent: Bool) async throws {
        if isAgent {
            _ = try await call("agent.focus", params: ["target": paneId])
        } else {
            _ = try await call("pane.focus", params: ["pane_id": paneId])
        }
    }

    // MARK: Worktrees

    /// Worktrees of the repo that `workspaceId` runs in. Fails with `not_git_worktree`
    /// when the workspace isn't inside a git checkout.
    public func worktrees(of workspaceId: String) async throws -> [Worktree] {
        try await call("worktree.list", params: ["workspace_id": workspaceId], key: "worktrees", as: [Worktree].self)
    }

    public struct WorktreeWorkspace: Decodable, Sendable {
        public let workspace: Workspace
        public let rootPane: Pane
    }

    /// Creates a branch and worktree from the workspace's repo and opens it in a new
    /// workspace. Passing the source workspace keeps herdr from opening a second
    /// workspace for the main checkout.
    public func createWorktree(from workspaceId: String, branch: String, base: String?) async throws -> WorktreeWorkspace {
        var params: [String: Any] = ["workspace_id": workspaceId, "branch": branch, "focus": false]
        if let base, !base.isEmpty { params["base"] = base }
        let data = try await call("worktree.create", params: params)
        return try HerdrJSON.decoder.decode(WorktreeWorkspace.self, from: data)
    }

    /// Opens an existing worktree of the workspace's repo in a new workspace.
    public func openWorktree(from workspaceId: String, path: String) async throws -> Workspace {
        try await call(
            "worktree.open",
            params: ["workspace_id": workspaceId, "path": path, "focus": false],
            key: "workspace", as: Workspace.self
        )
    }

    /// Deletes the worktree checkout behind a linked-worktree workspace and closes the
    /// workspace. Without `force`, herdr refuses when there are uncommitted changes
    /// (`dirty_worktree_requires_force`). The branch itself is kept.
    public func removeWorktree(_ workspaceId: String, force: Bool) async throws {
        _ = try await call("worktree.remove", params: ["workspace_id": workspaceId, "force": force])
    }

    /// Agent kinds this server can detect and start, in herdr's order.
    public func agentKinds() async throws -> [String] {
        struct Manifest: Decodable { let agent: String }
        return try await call("server.agent_manifests", key: "manifests", as: [Manifest].self).map(\.agent)
    }

    // MARK: Response parsing

    private static func result(of reply: Data, method: String) throws -> Data {
        guard let object = try? JSONSerialization.jsonObject(with: reply) as? [String: Any] else {
            throw HerdrError.decoding("\(method): reply is not a JSON object")
        }
        if let error = object["error"] as? [String: Any] {
            throw HerdrError.server(
                code: error["code"] as? String ?? "unknown",
                message: error["message"] as? String ?? ""
            )
        }
        guard let result = object["result"] else {
            throw HerdrError.decoding("\(method): reply has no result")
        }
        return try JSONSerialization.data(withJSONObject: result)
    }
}

/// Lets exactly one of several racing callbacks resume a continuation.
private final class Once: @unchecked Sendable {
    private let lock = NSLock()
    private var claimed = false

    func claim() -> Bool {
        lock.withLock {
            defer { claimed = true }
            return !claimed
        }
    }
}

// MARK: - Events

public extension HerdrClient {
    /// Opens a dedicated connection and streams pushed events for `subscriptions`.
    /// Each subscription is a dict like `["type": "pane.created"]`.
    /// The stream ends when herdr closes the connection (including `events_lost`);
    /// callers should resnapshot and resubscribe.
    static func events(socketPath: String, subscriptions: [[String: Any]]) -> AsyncThrowingStream<HerdrEvent, Error> {
        AsyncThrowingStream { continuation in
            let socket: LineSocket
            do {
                socket = try LineSocket(path: socketPath)
                let request: [String: Any] = [
                    "id": "paca_sub",
                    "method": "events.subscribe",
                    "params": ["subscriptions": subscriptions],
                ]
                try socket.send(JSONSerialization.data(withJSONObject: request))
            } catch {
                continuation.finish(throwing: error)
                return
            }

            socket.startReading(
                onLine: { line in
                    guard let object = try? JSONSerialization.jsonObject(with: line) as? [String: Any] else { return }
                    if let error = object["error"] as? [String: Any] {
                        continuation.finish(throwing: HerdrError.server(
                            code: error["code"] as? String ?? "unknown",
                            message: error["message"] as? String ?? ""
                        ))
                        socket.close()
                        return
                    }
                    guard let kind = object["event"] as? String,
                          let payload = object["data"],
                          let data = try? JSONSerialization.data(withJSONObject: payload) else { return }
                    continuation.yield(HerdrEvent(kind: kind, data: data))
                },
                onClose: { continuation.finish() }
            )
            continuation.onTermination = { _ in socket.close() }
        }
    }
}

// MARK: - Sessions

/// One named herdr session from `herdr session list --json`.
public struct HerdrSession: Decodable, Hashable, Sendable, Identifiable {
    public let name: String
    public let running: Bool
    public let socketPath: String
    public let isDefault: Bool

    public var id: String { name }

    enum CodingKeys: String, CodingKey {
        case name, running, socketPath
        case isDefault = "default"
    }
}

/// Sessions are separate herdr servers, each with its own socket, so they're managed
/// through the `herdr` CLI rather than the socket API.
public enum HerdrSessions {
    public static func list() async throws -> [HerdrSession] {
        struct Listing: Decodable { let sessions: [HerdrSession] }
        let output = try await run(["session", "list", "--json"])
        do {
            return try HerdrJSON.decoder.decode(Listing.self, from: output).sessions
        } catch {
            throw HerdrError.decoding("herdr session list: \(error)")
        }
    }

    /// Starts a headless server for `name` (creating the session if it's new) and waits
    /// until its socket answers. Names may use ASCII letters, numbers, `.`, `_` and `-`.
    public static func start(_ name: String, timeout: Duration = .seconds(10)) async throws {
        guard let binary = TerminalSession.herdrBinary() ?? which("herdr") else {
            throw HerdrError.socket("Couldn't find the herdr command. Install herdr or set HERDR_BIN_PATH.")
        }
        guard name.range(of: #"^[A-Za-z0-9._-]+$"#, options: .regularExpression) != nil else {
            throw HerdrError.server(code: "invalid_session_name", message: "Session names may only use letters, numbers, '.', '_' and '-'.")
        }
        // Detach through sh so the server outlives Paca. The default session takes no `--session`.
        let shell = Process()
        shell.executableURL = URL(fileURLWithPath: "/bin/sh")
        shell.arguments = name == "default"
            ? ["-c", "nohup \"$0\" server >/dev/null 2>&1 &", binary]
            : ["-c", "nohup \"$0\" --session \"$1\" server >/dev/null 2>&1 &", binary, name]
        shell.environment = cleanEnvironment()
        try shell.run()
        shell.waitUntilExit()

        let client = HerdrClient(socketPath: HerdrClient.defaultSocketPath(session: name))
        let deadline = ContinuousClock.now + timeout
        while true {
            do {
                _ = try await client.ping()
                return
            } catch where ContinuousClock.now < deadline {
                try await Task.sleep(for: .milliseconds(250))
            }
        }
    }

    /// Stops the session's server. Every agent and shell in it ends.
    public static func stop(_ name: String) async throws {
        _ = try await run(["session", "stop", name])
    }

    /// Deletes a stopped session and its saved state. herdr refuses running sessions.
    public static func delete(_ name: String) async throws {
        _ = try await run(["session", "delete", name])
    }

    /// Runs `herdr ARGS`, returns stdout, and turns a failure into herdr's own message.
    /// herdr reports some errors as JSON and others as plain text, on either stream.
    static func run(_ args: [String]) async throws -> Data {
        guard let binary = TerminalSession.herdrBinary() ?? which("herdr") else {
            throw HerdrError.socket("Couldn't find the herdr command. Install herdr or set HERDR_BIN_PATH.")
        }
        return try await withCheckedThrowingContinuation { cont in
            let process = Process()
            let out = Pipe(), err = Pipe()
            process.executableURL = URL(fileURLWithPath: binary)
            process.arguments = args
            process.environment = cleanEnvironment()
            process.standardOutput = out
            process.standardError = err
            process.terminationHandler = { p in
                let stdout = out.fileHandleForReading.readDataToEndOfFile()
                let stderr = err.fileHandleForReading.readDataToEndOfFile()
                if p.terminationStatus == 0 {
                    cont.resume(returning: stdout)
                } else {
                    cont.resume(throwing: failure(stdout: stdout, stderr: stderr, args: args))
                }
            }
            do { try process.run() } catch { cont.resume(throwing: error) }
        }
    }

    private static func failure(stdout: Data, stderr: Data, args: [String]) -> HerdrError {
        for stream in [stdout, stderr] {
            if let object = try? JSONSerialization.jsonObject(with: stream) as? [String: Any],
               let error = object["error"] as? [String: Any] {
                return .server(code: error["code"] as? String ?? "cli", message: error["message"] as? String ?? "")
            }
        }
        let text = (String(data: stderr, encoding: .utf8) ?? "")
            .split(separator: "\n").first.map(String.init)?
            .replacingOccurrences(of: "error: ", with: "") ?? ""
        return .server(code: "cli", message: text.isEmpty ? "herdr \(args.joined(separator: " ")) failed" : text)
    }

    /// The caller's environment minus pane context, so the CLI can't target the wrong session.
    private static func cleanEnvironment() -> [String: String] {
        var env = ProcessInfo.processInfo.environment
        for key in ["HERDR_ENV", "HERDR_SOCKET_PATH", "HERDR_PANE_ID", "HERDR_TAB_ID", "HERDR_WORKSPACE_ID", "HERDR_SESSION"] {
            env.removeValue(forKey: key)
        }
        return env
    }

    private static func which(_ command: String) -> String? {
        let paths = (ProcessInfo.processInfo.environment["PATH"] ?? "").split(separator: ":")
        return paths.map { "\($0)/\(command)" }.first { FileManager.default.isExecutableFile(atPath: $0) }
    }
}

// MARK: - Remote machines

/// One saved SSH machine from `herdr machine list --json`. herdr owns this list; its TUI shows
/// the same machines.
public struct HerdrMachine: Decodable, Hashable, Sendable, Identifiable {
    public let id: String
    public let label: String
    /// What `ssh` connects to: a host alias from ~/.ssh/config or `user@host`.
    public let target: String
    /// herdr session on the remote machine.
    public let session: String
    public let enabled: Bool
}

public enum HerdrMachines {
    public static func list() async throws -> [HerdrMachine] {
        let output = try await HerdrSessions.run(["machine", "list", "--json"])
        do {
            return try HerdrJSON.decoder.decode([HerdrMachine].self, from: output)
        } catch {
            throw HerdrError.decoding("herdr machine list: \(error)")
        }
    }

    /// Saves `target` as a machine. herdr installs its matching version on the remote when it's
    /// missing and asks for a yes on a terminal first, so this runs it under `script` (a pty) and
    /// answers yes. Callers must tell the person about the install before calling.
    public static func add(target: String, label: String) async throws {
        guard let binary = TerminalSession.herdrBinary() else {
            throw HerdrError.socket("Couldn't find the herdr command. Install herdr or set HERDR_BIN_PATH.")
        }
        let output: String = try await withCheckedThrowingContinuation { cont in
            let process = Process()
            let input = Pipe(), out = Pipe()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/script")
            process.arguments = ["-q", "/dev/null", binary, "machine", "add", target, "--label", label]
            process.standardInput = input
            process.standardOutput = out
            process.standardError = out
            process.terminationHandler = { _ in
                let text = String(decoding: out.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
                cont.resume(returning: text.replacingOccurrences(of: "\r", with: ""))
            }
            do {
                try process.run()
                // The install prompt is the only question `machine add` asks.
                input.fileHandleForWriting.write(Data("y\n".utf8))
            } catch {
                cont.resume(throwing: error)
            }
        }
        guard output.contains("Saved SSH machine") else {
            let reason = output.split(separator: "\n").last { $0.lowercased().contains("error") }
                ?? output.split(separator: "\n").last ?? "herdr machine add failed"
            throw HerdrError.server(code: "machine_add_failed", message: String(reason).replacingOccurrences(of: "Error: ", with: ""))
        }
    }

    public static func remove(_ machine: HerdrMachine) async throws {
        _ = try await HerdrSessions.run(["machine", "remove", machine.id])
    }
}

/// SSH tunnel that makes a remote herdr look local: forwards the remote session's `herdr.sock`
/// (socket API) and `herdr-client.sock` (terminal streams) to a private local folder. Point
/// `HerdrClient` and `TerminalSession` at `socketPath`; the CLI finds the client socket next to it.
/// Uses key-based SSH only (`BatchMode`), so it never hangs on a password prompt.
public final class SSHTunnel: @unchecked Sendable {
    public let machine: HerdrMachine
    public let socketPath: String
    private let folder: String
    private let lock = NSLock()
    private var process: Process?

    public init(machine: HerdrMachine) {
        self.machine = machine
        // Unix socket paths max out at 104 bytes, so keep the folder short.
        folder = (NSTemporaryDirectory() as NSString).appendingPathComponent("paca-ssh/\(machine.id.prefix(8))")
        socketPath = (folder as NSString).appendingPathComponent("herdr.sock")
    }

    deinit { stop() }

    public var isRunning: Bool { lock.withLock { process?.isRunning == true } }

    /// Opens the tunnel (if it isn't up) and waits until the remote herdr answers `ping`.
    public func start(timeout: Duration = .seconds(20)) async throws {
        if isRunning, (try? await HerdrClient(socketPath: socketPath).ping()) != nil { return }
        stop()
        let remoteDir = try await remoteSessionFolder()
        try FileManager.default.createDirectory(atPath: folder, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])

        let ssh = Process()
        let err = Pipe()
        ssh.executableURL = URL(fileURLWithPath: "/usr/bin/ssh")
        ssh.arguments = Self.options + [
            "-N",
            "-o", "ExitOnForwardFailure=yes",
            "-o", "StreamLocalBindUnlink=yes",
            "-L", "\(socketPath):\(remoteDir)/herdr.sock",
            "-L", "\((folder as NSString).appendingPathComponent("herdr-client.sock")):\(remoteDir)/herdr-client.sock",
            machine.target,
        ]
        ssh.standardError = err
        ssh.standardOutput = FileHandle.nullDevice
        try ssh.run()
        lock.withLock { process = ssh }

        let client = HerdrClient(socketPath: socketPath)
        let deadline = ContinuousClock.now + timeout
        while true {
            if !ssh.isRunning {
                let reason = String(decoding: err.fileHandleForReading.availableData, as: UTF8.self)
                throw HerdrError.socket("SSH to \(machine.target) failed: \(reason.trimmingCharacters(in: .whitespacesAndNewlines))")
            }
            if (try? await client.ping()) != nil { return }
            guard ContinuousClock.now < deadline else {
                stop()
                throw HerdrError.socket("herdr on \(machine.label) didn't answer within \(timeout). Is its server running? Try `herdr --remote \(machine.target)` once.")
            }
            try await Task.sleep(for: .milliseconds(300))
        }
    }

    public func stop() {
        let running = lock.withLock { () -> Process? in
            defer { process = nil }
            return process
        }
        if running?.isRunning == true { running?.terminate() }
    }

    /// `$HOME/.config/herdr` for the default session, `.../sessions/NAME` otherwise.
    private func remoteSessionFolder() async throws -> String {
        let home = try await Self.ssh(machine.target, command: "printf %s \"$HOME\"")
        guard home.hasPrefix("/") else { throw HerdrError.socket("Couldn't read the home folder on \(machine.target).") }
        let base = "\(home)/.config/herdr"
        return machine.session == "default" ? base : "\(base)/sessions/\(machine.session)"
    }

    static let options = ["-o", "BatchMode=yes", "-o", "ConnectTimeout=8", "-o", "ServerAliveInterval=15", "-o", "ServerAliveCountMax=3"]

    /// Runs one command over SSH and returns its stdout. Fails with ssh's own error text.
    static func ssh(_ target: String, command: String) async throws -> String {
        try await withCheckedThrowingContinuation { cont in
            let p = Process()
            let out = Pipe(), err = Pipe()
            p.executableURL = URL(fileURLWithPath: "/usr/bin/ssh")
            p.arguments = options + [target, command]
            p.standardOutput = out
            p.standardError = err
            p.terminationHandler = { p in
                let stdout = String(decoding: out.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
                let stderr = String(decoding: err.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
                if p.terminationStatus == 0 {
                    cont.resume(returning: stdout)
                } else {
                    let reason = stderr.trimmingCharacters(in: .whitespacesAndNewlines)
                    cont.resume(throwing: HerdrError.socket("SSH to \(target) failed: \(reason.isEmpty ? "exit \(p.terminationStatus)" : reason)"))
                }
            }
            do { try p.run() } catch { cont.resume(throwing: error) }
        }
    }
}
