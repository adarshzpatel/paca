# Paca plan

A native macOS client for [herdr](https://herdr.dev). Slack-style main window, an always-on menu bar panel, and a foundation for an agent orchestrator later.

Facts below were checked against herdr 0.9.0 (socket protocol 22) on this Mac on 2026-10-03.

## What herdr gives us

herdr is a background server that owns the terminals (PTYs) your agents run in. The TUI is one client. A GUI can be another.

| Need | herdr surface |
|---|---|
| Connect | Unix socket at `~/.config/herdr/herdr.sock`. Named sessions live at `~/.config/herdr/sessions/<name>/herdr.sock`. |
| Protocol | Newline-delimited JSON. Request `{"id","method","params"}`, reply `{"id","result"}` or `{"id","error":{"code","message"}}`. |
| Full state | `session.snapshot` returns workspaces, tabs, panes, agents, and layouts in one call. |
| Live updates | `events.subscribe` holds the connection open and pushes events. 27 subscription types, including `pane.agent_status_changed`, `pane.agent_detected`, `pane.output_matched`, `layout.updated`. No replay. On `events_lost` the server closes the stream, so the client must resnapshot. |
| Agent state | `idle`, `working`, `blocked` (approval or question on screen), `done` (finished, not yet seen), `unknown`. |
| Drive agents | `agent.start`, `agent.prompt` (with optional wait), `agent.wait`, `agent.send_keys`, `agent.read`, `agent.focus`. 24 agent kinds, including claude, codex, gemini, cursor, opencode, amp. |
| Layout | `workspace.*`, `tab.*`, `pane.split/move/zoom/close`, `worktree.create/open/remove`. |
| Live terminal | `herdr terminal session observe <pane> --cols N --rows N` streams NDJSON lines of `{"bytes":"<base64 VT data>"}`. `control` is the read-write version and takes JSON commands for input, resize, scroll and mouse. I ran `observe` against a local pane and got a valid VT stream. |
| Schema | `herdr api schema --json` prints the full JSON Schema (102 methods). We generate Swift types from it. |
| Remote | Forward the remote socket with `ssh -L`. Everything else stays identical. |

When no client is attached, panes render at `server.headless_cols` x `server.headless_rows` (default 120x40).

## Prior art: herdrm

[herdrm](https://github.com/lcandy2/herdrm) already exists. It is a SwiftUI app with SwiftTerm terminals, an NDJSON socket client (`HerdrKit`), SSH tunnels, notifications, and a ⌘K palette. It has no menu bar panel and no Slack-style layout, and its README calls it early-stage.

Recommendation: build our own app. The orchestrator goal needs an event log and an action layer that herdrm doesn't have, and the UI direction is different. Read `HerdrKit` for protocol edge cases. Check its license before copying any code.

## Product shape

Three surfaces share one data store.

### 1. Main window (Slack layout)

| Slack | Paca |
|---|---|
| Workspace rail (far left icons) | Machines and sessions (this Mac, remote boxes) |
| Sidebar sections | herdr workspaces (projects) |
| Channels | Agents and plain panes, each with a status dot |
| Unread bold | `done` and not yet seen |
| Mention badge | `blocked`, needs you |
| Activity / Inbox | "Needs you" view, every blocked and done agent across machines |
| Channel view | Agent view, live terminal plus header |
| Message composer | Prompt box that calls `agent.prompt` |
| Thread panel (right) | Pane details, sibling panes, worktree, git branch |
| ⌘K switcher | Same, across all machines |

```
┌──┬──────────────────────┬─────────────────────────────────────────────┬─────────────┐
│◉ │ herdr        🔔 🔍   │ ● reviewer · claude · ~/morphic/studio   ⋯  │ Details     │
│  │                      │ [Terminal] [Transcript] [Info]              │             │
│M │ ⚑ Needs you      2   │                                             │ Pane wM:pE  │
│  │ ✎ New agent          │  live PTY (SwiftTerm), full TUI fidelity    │ Tab 1       │
│R │                      │                                             │ Branch main │
│  │ studio               │                                             │ Worktree –  │
│+ │   ◐ reviewer         │                                             │             │
│  │   ● fixer        ⚑   │                                             │ Siblings    │
│  │   ○ server           │                                             │  ○ server   │
│  │ Developer            │                                             │             │
│  │   ◐ paca             │ ┌─────────────────────────────────────────┐ │             │
│  │                      │ │ Prompt reviewer…            claude  ⏎   │ │             │
│AP│                      │ └─────────────────────────────────────────┘ │             │
└──┴──────────────────────┴─────────────────────────────────────────────┴─────────────┘
```

Agent view tabs:

- Terminal: live, interactive PTY through `terminal session control`.
- Transcript: `agent.read --source recent-unwrapped`, plain selectable text, searchable.
- Info: kind, session id, cwd, process info, status history.

When an agent is `blocked`, the composer locks and shows "Waiting for approval. Answer in the terminal." `agent.prompt` rejects blocked agents anyway, and approvals should happen where you can see what you're approving.

### 2. Menu bar item and always-on panel

The menu bar item is the main way you track agents. It runs even when the main window is closed, and the app can live there alone (no Dock icon) if you turn that on in settings.

Menu bar icon states:

| State | Icon | Text |
|---|---|---|
| Nothing running | gray herd glyph | none |
| Agents working | glyph with spinning ring | `◐3` |
| Something blocked | amber glyph | `⚑2 ◐3` |
| Something finished, unseen | green dot on glyph | `✓1` |
| herdr server down | glyph with slash | none |

The counts are optional. Some people want only the glyph.

- Click the icon, or press a global hotkey (default ⌥Space, configurable), to open a floating `NSPanel` under it. The panel is non-activating, floats above other windows, follows you across Spaces, and works over full-screen apps.
- Right-click the icon for a quick menu: open main window, new agent, mute notifications for 1 hour, quit.
- Panel lists agents in three groups: Needs you, Working, Done. Each row shows status, name, workspace, the last output line, and time in state.
- Each row has a one-line quick prompt. Enter sends, ⌘Enter opens the agent in the main window.
- Later: an optional thin pill at the screen edge that pulses when an agent blocks.

### 3. Notifications

- `UNUserNotificationCenter` alerts on `→ blocked` and `→ done`, grouped per agent, with per-workspace mute.
- Clicking a notification focuses that agent in the main window.
- v1 does not answer approvals from a notification. You approve where you can read the screen.

## Architecture

Swift 6, SwiftUI for views, AppKit where SwiftUI is weak (NSPanel, status item, window chrome, terminal host). Target macOS 14+.

```
Paca.app
├─ HerdrProtocol   Codable types generated from `herdr api schema --json`
├─ HerdrClient     NWConnection on unix socket, NDJSON framing, id-matched
│                  async requests, AsyncStream of events, reconnect + resnapshot
├─ HerdrStore      @Observable state per machine: snapshot + applied events
├─ TerminalBridge  spawns `herdr terminal session control`, base64 → terminal view,
│                  keystrokes/resize → JSON commands
├─ Actions         one entry point for every mutation (start, prompt, split, close)
├─ EventLog        SQLite (GRDB): every status transition with timestamps
├─ Machines        ssh -L tunnels, per-machine client + store
└─ UI              MainWindow, MenuBarPanel, Notifier, CommandPalette
```

Choices:

- Terminal renderer. SwiftTerm for v1. herdrm proves it works with herdr, and it accepts raw VT bytes. Swap in libghostty later if rendering gets slow with many live panes.
- Terminal transport. Use the `herdr terminal session control` CLI, not the private binary protocol. The CLI is the supported surface and the binary protocol changes with each install.
- Types. Generate from the schema with a script in `scripts/gen-protocol.sh`, so a protocol bump is one rerun. On connect, call `ping` and check the server's method list before using newer features.
- Only stream terminals that are on screen. Everything else uses events and cheap `agent.read` calls.

### Built for the orchestrator later

The orchestrator should not need a rewrite of the app. Two rules make that work:

1. Every mutation goes through `Actions`. The UI calls it today. Rules, scripts, and an LLM planner call the same functions later.
2. `EventLog` records every status change from day one. That history powers timelines, "time blocked" metrics, and triggers like "when `reviewer` is done, prompt `fixer` with its output".

Orchestrator ideas for later, not v1: recipes (spawn a reviewer + fixer pair on a worktree), an agent-to-agent handoff graph, a kanban of tasks mapped to agents, cost and token tracking per agent.

## Visual design

Match the Codex desktop look in the reference screenshots.

- Dark neutral base around `#111`, sidebar one step lighter with `.sidebar` vibrancy.
- SF Pro 13pt for UI, SF Mono or JetBrains Mono for terminals.
- 8pt corner radius, hairline separators, SF Symbols at regular weight.
- Status colors: working = blue spinning ring, blocked = amber flag, done = green dot until seen, idle = gray hollow circle, unknown = gray dashed circle.
- Full light mode from the start. Cheaper than retrofitting.

## Milestones

| # | Scope | Estimate |
|---|---|---|
| M0 | Spike. Socket client does `ping`, `session.snapshot`, `events.subscribe` and prints events. One SwiftTerm view shows a live pane and accepts typing. | 1 day |
| M1 | Read-only Slack window. Machine rail, sidebar with live status, agent view with live terminal. | 3 to 4 days |
| M2 | Interaction. Composer → `agent.prompt`, "New agent" sheet (kind, workspace, worktree), ⌘K, rename, close. | 2 to 3 days |
| M3 | Always-on. Menu bar item, floating panel, global hotkey, notifications. | 2 days |
| M4 | Remote machines over `ssh -L` with reconnect. | 2 to 3 days |
| M5 | Orchestrator groundwork. Event log UI, first rule ("when X done, prompt Y"). | Later |

M0 through M3 is about two weeks of focused work.

## M2 plan: make Paca read-write

Checked against herdr 0.9.0 (protocol 22) on 2026-10-03.

Paca started read-only, calling 2 of herdr's 128 socket methods (`ping` and `session.snapshot`). The prompt bar that used `agent.prompt` was removed on 2026-10-03. Everything below already exists in herdr. The work is UI plus a thin action layer.

### Status

- [x] Phase 1. Action layer (2026-10-03)
- [x] Phase 2. Workspaces (2026-10-03)
- [x] Phase 3. Shells and agents (2026-10-03)
- [x] Phase 4. Worktrees (2026-10-03)
- [x] Phase 5. Sessions (2026-10-03)
- [x] Liquid Glass fix (2026-10-03, needs an eye check on screen)
- [x] Glass removed (2026-10-05): solid window only; colors come from Base16 themes that can match herdr's
- [x] Draggable sidebar edge (2026-10-03, needs a hands-on check)
- [x] ⌘K switcher (2026-10-03)
- [x] M3: notifications on blocked/done, ⌥Space floating panel (2026-10-03, hotkey needs a hands-on check)
- [x] M4: remote machines over SSH (2026-10-04, tested against a Colima VM)
- [x] M5: orchestrator groundwork, activity log and rules (2026-10-04, prompt delivery needs a test with two real agents)

Check after each phase: `scripts/smoke-actions.sh` (every action against `paca-test`), `scripts/test.sh`, then `scripts/install.sh` to put the build in /Applications.

### Phase 1. Action layer (done 2026-10-03)

- `HerdrStore` has one async function per mutation (the `// MARK: Actions` section), each going through `perform(_:_:)`. Views call the store, never the client. This is the `Actions` entry point from the architecture section.
- No optimistic updates. Each action waits for herdr's reply, then resnapshots. Lifecycle events from other clients (the TUI, the CLI) refresh too. Added subscriptions: `workspace.moved`, `workspace.reordered`, `tab.renamed`. Left out `pane.updated`, which likely fires on every terminal title change and would resnapshot constantly.
- Failures show as a dismissible banner at the bottom of the sidebar with herdr's own message (`HerdrError.userMessage`), plus a `PACA_DEBUG=1` log line. A single banner was simpler than inline errors on every control.
- Fixed a protocol bug found while doing this: herdr answers one request per connection and then closes it. `HerdrClient` used to keep one connection, so every call after the first failed and the app silently reconnected after each event. `call()` now opens a short-lived socket per request.
- `scripts/smoke-actions.sh` runs `paca-probe --session paca-test smoke`, which calls each `HerdrClient` action and checks the result in a fresh snapshot. It refuses the default session. `scripts/tools/herdr-call.py METHOD '{json}'` sends one raw request for experiments (defaults to `paca-test`).

### Phase 2. Workspaces (done 2026-10-03)

| Action | Method | UI |
|---|---|---|
| New | `workspace.create` (`cwd`, `label`, `focus: false`) | "+" on the Workspaces heading opens a folder picker. The label is the folder name |
| Rename | `workspace.rename` (`workspace_id`, `label`) | Context menu → Rename…, then an inline field. Return or clicking away saves, Escape cancels |
| Close | `workspace.close` (`workspace_id`) | Context menu → Close Workspace…. Asks first when the workspace has any agent, and says how many are mid-task |
| Reorder | `workspace.move` (`workspace_id`, `insert_index`) | Drag a workspace onto another to take its place. `insert_index` is the 0-based final position |

Not done: rename by double-click (it would fight the row's expand/collapse click).

### Phase 3. Shells and agents (done 2026-10-03)

| Action | Method | UI |
|---|---|---|
| New shell | `tab.create` (`workspace_id`), reply's `root_pane` | Workspace context menu → New Shell. Opens a tab and selects its shell |
| Split | `pane.split` (`target_pane_id`, `direction` right/down) | Pane context menu → Split Right / Split Down. Selects the new shell |
| New agent | `tab.create`, then `agent.start` (`pane_id`, `kind`, `name`) | "New agent" row under Needs you, or workspace context menu → New Agent…. The sheet picks workspace, kind and name (defaults to the kind). If `agent.start` fails, the new tab is closed again |
| Rename | `agent.rename` (`target`, `name`) for agents, `pane.rename` (`pane_id`, `label`) for shells | Pane context menu → Rename…, inline field |
| Close | `pane.close` (`pane_id`) | Pane context menu. Asks first only when the agent is `working` or `blocked`. Closing a tab's last pane closes the tab |
| Show in herdr | `agent.focus` (`target`) for agents, `pane.focus` (`pane_id`) for shells | Pane context menu |

What I learned while building it:

- `agent.start` doesn't wait. It replies straight away with `launch_pending: true`, and the snapshot's `agents` entry keeps `launch_pending` until the agent is ready. herdr refuses `agent.rename` until then (`agent_launch_pending`). Paca shows a spinner on the row and disables Rename while it's pending.
- Agent names live only in the snapshot's `agents` list, not on panes. Paca used to ignore that list, so agents showed their terminal title ("Claude Code"). `SessionSnapshot` now copies the name and pending flag onto each `Pane`, and `displayName` prefers the name.
- Agent kinds come from `server.agent_manifests` (21 on herdr 0.9.0). The CLI help lists 23; `omp` and `mastracode` have no manifest, so Paca doesn't offer them.

Not done: ⌘W to close a pane. On macOS ⌘W closes the window, and taking it over would surprise people. The context menu covers it for now. `agent.prompt` stays out on purpose.

### Phase 4. Worktrees (done 2026-10-03)

| Action | Method | UI |
|---|---|---|
| Agent on a new worktree | `worktree.create` (`workspace_id` of the source, `branch`), then `agent.start` in the reply's `root_pane` | New agent sheet → "Start on a new worktree". The branch defaults to the agent name as a slug |
| List and open | `worktree.list` (`workspace_id`), `worktree.open` (`workspace_id`, `path`) | Workspace context menu → Worktrees… lists branch and path, with Open for the ones not open yet |
| Remove | `worktree.remove` (`workspace_id`, `force`) | Workspace context menu → Remove Worktree…, only on linked-worktree workspaces. First confirmation says the branch stays. If herdr answers `dirty_worktree_requires_force`, a second confirmation lists up to 6 uncommitted files (from `git status --porcelain`) before retrying with `force` |

What I learned while building it:

- Always pass the source `workspace_id` to `worktree.create`. With only `cwd`, herdr also opens a second workspace for the main checkout.
- herdr checks worktrees out to `~/.herdr/worktrees/<repo folder name>/<branch>`. `worktree.remove` deletes the checkout and closes its workspace but keeps the branch, and leaves the empty `<repo folder name>` folder behind.
- A workspace made with `workspace.create` in a git folder reports no `worktree` info, so Paca can't tell in advance whether worktree actions will work. The options always show, and herdr's `not_git_worktree` message explains when the folder isn't a repo.
- A new pane's shell may still be starting when `agent.start` arrives. herdr answers `agent_pane_busy`, and `HerdrClient.startAgent` now retries that for up to 10 seconds. Without the retry, New agent failed about one time in three.
- If the agent fails to start on a new worktree, Paca keeps the worktree (it may already hold the branch you wanted) and reports the error.

Not done: choosing a base branch other than the current one (`base` is supported by the client, not shown in the sheet).

### Phase 5. Sessions (done 2026-10-03)

Sessions are separate herdr servers, each with its own socket, so `HerdrSessions` (in HerdrKit) drives the `herdr` CLI instead of the socket API:

| Action | How | UI |
|---|---|---|
| List | `herdr session list --json` (name, running, socket_path, default) | Rail: one tile per running session (first letter, "D" for default). The current one is outlined |
| Switch | Store cancels its event loop, points at the session's socket and resnapshots | Click a tile. Paca remembers the last session (`paca.lastSession`) and falls back to default if it has stopped |
| New | `herdr --session NAME server` detached through `sh -c nohup`, then `ping` until the socket answers (10 s) | Rail "+" → New Session…, then switches to it |
| Start | Same as New, for a stopped session | Rail "+" → Stopped → name → Start |
| Stop | `herdr session stop NAME` | Tile context menu → Stop Session…, always confirmed. Stopping the current session moves Paca to default |
| Delete | `herdr session delete NAME` | Rail "+" → Stopped → name → Delete…, always confirmed |

What I learned while building it:

- herdr refuses to delete a running session (`session_delete_failed`) and validates names itself (ASCII letters, numbers, `.`, `_`, `-`). Paca checks the name first so the error reads well.
- CLI errors come back as JSON or plain text, on stdout or stderr depending on the command. `HerdrSessions.run` handles all four.
- An app opened from Finder doesn't have your shell's PATH. The CLI is found through `HERDR_BIN_PATH`, then `~/.local/bin`, `/opt/homebrew/bin`, `/usr/local/bin` (shared with the terminal bridge).
- Each event loop now keeps its own client and socket path and drops its results once cancelled, so switching sessions never flashes the old session's data.

### Window polish (done 2026-10-03)

- **Liquid Glass.** The "Liquid Glass" style never used Liquid Glass: the window background was the old behind-window blur with an 82% opaque gray on top, and the sidebar added a 55% fill. On macOS 26 the window background is now `NSGlassEffectView` (`.regular`, or `.clear` for Clear glass) with no tint, and the sidebar has no fill, following Apple's "remove custom backgrounds from sidebars" guidance. macOS 14 and 15 keep the old blur and tint. The terminal stays opaque. `scripts/snapshot.sh` can't render glass (it shows white), so check it on screen; `screencapture` needs Screen Recording permission for the terminal.
- **Sidebar edge.** Drag the line between sidebar and detail to resize (220 to 480 pt, saved as `paca.sidebarWidth`). Dragging below 150 pt closes the sidebar; ⌘B or the toolbar button reopens it at the last width. The grab area is 9 pt wide with a resize cursor, and VoiceOver can adjust it in 20 pt steps.

### ⌘K switcher (done 2026-10-03)

⌘K opens a palette over the window with every agent, shell and workspace in the current session. Empty, it lists agents that need you first, then other agents, shells, and workspaces. Typing ranks matches: title prefix, word prefix, anywhere in the title, the subtitle (kind · workspace), then letters in order. ↑/↓ move, Return opens, Esc or a click outside closes. A pane opens in the detail view; a workspace opens its first agent, or its first shell. `--palette QUERY` opens it at launch for scripted screenshots (`scripts/snapshot.sh out.png --session paca-test --palette tm`).

### M3: always-on (done 2026-10-03)

- **Notifications.** `SessionSnapshot.attentionTransitions(since:)` (unit-tested) finds agents that just became `blocked` or `done`. Paca posts one notification per agent and state ("reviewer needs you", "reviewer is done"), with a sound only for blocked. A repeat replaces the earlier one. No notification for the agent you're looking at while Paca is in front. Clicking one switches to its session if needed and opens the agent. Settings has a toggle. Connecting or switching sessions never replays old states.
- **Signing.** macOS refused notifications from the unsigned bundle (`UNErrorDomain` 1). `scripts/install.sh` now ad-hoc signs the app (`local.paca.Paca`). That needed the SwiftPM resource bundles moved into Contents/Resources (files at the bundle root block signing), and `Brand` now looks there before `Bundle.module`. SwiftTerm's bundle only feeds its optional Metal renderer, which Paca doesn't use.
- **⌥Space panel.** A global hotkey (Carbon `RegisterEventHotKey`, no permissions) toggles a floating panel with the same agent list as the menu bar item, at the top right of the screen under the pointer. It floats over full-screen apps and every Space. Esc or clicking elsewhere closes it; picking an agent opens it in the main window. Settings can turn the hotkey off. ⌥Space types a non-breaking space in other apps, so the hotkey takes that over while it's on.
- **Testing.** `pane.report_agent` (`source`, `agent`, `state`) fakes a status change on a scratch pane, and `pane.release_agent` undoes it. That drove a real notification through the installed app. The hotkey can't be triggered from a script without Accessibility permission.
- Not done: per-workspace mute, a choice of hotkey, the screen-edge pill from the product sketch.

### M4: remote machines (done 2026-10-04)

- **Machines are herdr's.** Paca reads `herdr machine list --json` and adds or removes with `herdr machine add TARGET --label L` / `herdr machine remove ID`, so the herdr TUI and Paca share one list. `machine add` installs the matching herdr on the remote when it's missing, but only after a yes on a terminal; Paca runs it under `script` (a pty) and answers yes, and the Add Machine sheet says so before you click Add.
- **Tunnel.** `SSHTunnel` (HerdrKit) forwards two sockets from the remote session folder (`$HOME/.config/herdr`, or `.../sessions/NAME`) into `$TMPDIR/paca-ssh/<id>/`: `herdr.sock` for the socket API and `herdr-client.sock` for terminal streams. The local `herdr terminal session control` finds the client socket next to `HERDR_SOCKET_PATH` (it swaps `.sock` for `-client.sock`), so the live terminal works unchanged. Forwarding only the API socket fails with "failed to connect to server" from the terminal.
- **SSH.** Key-based only (`BatchMode=yes`), `ConnectTimeout=8`, keepalives every 15 s, `ExitOnForwardFailure`, `StreamLocalBindUnlink`. The tunnel waits for `ping` (20 s) and reports ssh's own error text when it fails.
- **Store.** Selecting a machine works like switching sessions: the event loop restarts against the tunnel's socket and reopens the tunnel before each reconnect attempt. Paca remembers the last machine (`paca.lastMachine`), notifications carry the machine, and clicking one switches back to it. The tunnel closes on quit.
- **UI.** Machine tiles sit under the session tiles, with a network badge (red while the connection fails). Right-click → Reconnect / Remove Machine…. "+" → Add Machine…. New workspace on a machine asks for a path on that machine instead of opening Finder's panel.
- **Testing.** `PACA_SMOKE_MACHINE=colima scripts/smoke-actions.sh` adds four remote steps (tunnel, create and close a workspace, terminal socket). `--machine LABEL` opens a machine at launch for scripted screenshots.
- Not done: password or 2FA SSH (needs an interactive prompt), switching the remote session from Paca, and showing every machine's agents at once in Needs you.

### M5: orchestrator groundwork (done 2026-10-04)

- **Activity log.** `SessionSnapshot.statusChanges(since:)` (unit-tested) diffs every agent's status between snapshots. Each change is one JSON line in `~/Library/Application Support/Paca/activity.jsonl` (trimmed to the newest 2,000 lines past 5 MB; newest 1,000 in memory). JSON Lines instead of SQLite/GRDB for now: no dependency, and the only query so far is "recent events for this target".
- **Activity view.** A clock button in the rail shows the log for the session or machine on screen, newest first: agent, `from → to`, time, how long it spent in the previous state, workspace. Rule runs show as their own rows, red when they failed. Clicking a row opens the agent.
- **Rules.** `AgentRule` (unit-tested): when agent `source` becomes `done`, `blocked` or `idle`, send `message` to agent `target`, optionally followed by the source's last 20/40/100 lines (`pane.read`, `recent_unwrapped`, ANSI stripped). Agents match by name, case-insensitive, on the current session or machine. A rule fires at most once a minute, so two rules can't ping-pong. Results (prompted, no such agent, herdr's refusal) land in the activity log, not the error banner. Rules live in `rules.json` next to the log. Activity → Rules… lists, toggles, deletes and adds them; the agent fields offer the agents on screen.
- **Delivery uses `agent.prompt`,** which herdr only accepts when the agent is the pane's foreground process, so a faked agent (`pane.report_agent`) is refused with `agent_not_ready`. The end-to-end test used that: a fake `faker` went working → blocked, the rule matched and fired, and the refusal was logged. A real handoff between two live agents hasn't been run, since it spends tokens.
- **Fix found while testing:** an explicit `--session` now beats the remembered machine.
- `--view activity|inbox` picks the sidebar view at launch for scripted screenshots.
- Not done: conditions beyond a state (e.g. "done and the output mentions tests failed"), chains with more than one target, a per-agent timeline in the detail view, metrics ("time blocked today").

### Confirmations

| Action | Confirm when |
|---|---|
| Close workspace | It has panes running agents |
| Close pane | Agent is `working` or `blocked` |
| Remove worktree with `force` | Always. Name the branch |
| Stop session | Always. Show the agent count |
| Delete session | Always |

### Testing

Run every action against the throwaway `paca-test` session (`scripts/test-session.sh start`), never the default one. `scripts/smoke-actions.sh` creates, renames and closes a workspace, tab, pane, agent and worktree through `HerdrClient` on `paca-test` and checks `session.snapshot` after each step (27 steps as of Phase 5, including a scratch session that is created, stopped and deleted), so a protocol change shows up before the UI breaks. It cleans up after itself even when a step fails. `PACA_SMOKE_AGENT=""` skips starting a real agent CLI.

Total: about 5 days. Phases 2 and 3 cover most of the "view only" complaint, so ship them first.

## M0 findings (2026-10-03, herdr 0.9.0)

Verified on a throwaway `paca-test` session:

- Control stdin takes `{"type":"terminal.input","bytes":"<base64>"}` (or `"text"`), `{"type":"terminal.resize","cols":N,"rows":N}`, `{"type":"terminal.scroll","direction":"up","lines":N}` and `{"type":"terminal.release"}`. Unknown fields are ignored without an error, so typos fail silently.
- Frames look like `{"type":"terminal.frame","seq":1,"full":true,"width":80,"height":12,"encoding":"ansi","bytes":"..."}`. The first frame is a full repaint and later ones are diffs.
- A second controller without `--takeover` gets `terminal.closed` with reason "already has an attached client". Paca shows that reason and a Take over button.
- With no TUI attached, the controller's size became the pane's real size (`viewport_rows` followed it). Still to check: what happens to a pane that your herdr TUI is showing at the same time.
- Pushed events look like `{"event":"pane_created","data":{...}}`.
- herdr closes a socket after answering one request. Every request needs its own connection; only `events.subscribe` stays open.
- `pane.agent_status_changed` requires a `pane_id`. There is no global status subscription, so Paca subscribes per pane and resubscribes when the pane set changes.

## Open questions

1. Does attaching from Paca resize a pane that the herdr TUI is also showing? Try it on a scratch pane first.
2. Whether `done` → seen should happen when Paca shows an agent. `agent.focus` marks it seen but also moves focus in the TUI.
3. herdrm's license, if we want to reuse any of `HerdrKit`.
