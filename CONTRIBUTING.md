# Contributing to Paca

Thanks for helping. Paca is a native macOS client for [herdr](https://herdr.dev),
written in Swift and SwiftUI. Bug reports, fixes, themes and ideas are all
welcome.

## Before you start

- **Small fix?** Open a pull request directly.
- **New feature or a big change?** Open an issue first so we can agree on the
  approach. It saves you from writing code that won't get merged.
- **Bug?** Use the bug report template. Include your macOS version, herdr
  version (`herdr --version`) and the steps that trigger it.

[docs/PLAN.md](docs/PLAN.md) describes how Paca talks to herdr and what's
planned. Read it before touching `HerdrKit`.

## Setup

You need macOS 14 or later, a Swift 6 toolchain (Command Line Tools is enough)
and herdr 0.9 or later.

```bash
git clone https://github.com/adarshzpatel/paca.git
cd paca
scripts/run.sh          # build and launch against your default herdr session
scripts/test.sh         # unit tests, works without Xcode
```

To experiment without touching your real agents, start a throwaway session:

```bash
scripts/test-session.sh start
scripts/run.sh --session paca-test
scripts/test-session.sh stop
```

Packaging the app icon (`scripts/install.sh`, `scripts/sync-brand.sh`) needs
Xcode 26. Day-to-day work doesn't.

## Project layout

| Path | What's there |
|---|---|
| `Sources/HerdrKit` | Socket client, models, terminal control bridge. No UI. |
| `Sources/PacaTheme` | Base16 parsing and WCAG contrast correction |
| `Sources/Paca` | The SwiftUI app |
| `Sources/paca-probe` | CLI for checking herdr state and theme contrast without the GUI |
| `Tests/` | Swift Testing suites for `HerdrKit` and `PacaTheme` |
| `scripts/` | Build, run, test and screenshot helpers. See the README table. |

## Checks before a pull request

```bash
scripts/test.sh
scripts/contrast.sh     # exits 1 if a built-in theme misses a contrast minimum
```

CI runs both on every pull request.

For UI changes, attach a screenshot in light and dark mode.
`scripts/snapshot.sh out.png` renders the window without Screen Recording
permission. Use a test session so your own pane names don't end up in the
picture.

## Code style

- Match the code around you. Paca uses doc comments (`///`) that say why, not
  what, and keeps them short.
- Draw colors from `Theme` in the main window. Views on system materials (the
  menu bar panel) use macOS system colors so they stay readable whatever theme
  is picked.
- New colors must pass `scripts/contrast.sh`, including `--increased`.
- Support Reduce Motion and VoiceOver labels on anything interactive.
- No new dependencies without discussing them in an issue first.

## Commits and pull requests

Commit subjects follow [Conventional Commits](https://www.conventionalcommits.org/),
50 characters max:

```
fix(menubar): use system colors in panel
feat(themes): read Ghostty cursor color
```

Keep each pull request to one change. Describe what changed, why, and how you
tested it.

## Themes

You don't need to touch code to add a theme. Drop a Base16 `.yaml` file into
`~/.config/paca/themes/`. To propose a new built-in theme, add it and make sure
`scripts/contrast.sh` passes.

## Name and logo

Code contributions are under the MIT license. The Paca name and artwork are
covered by [TRADEMARKS.md](TRADEMARKS.md).

## Conduct

Everyone here follows the [Code of Conduct](CODE_OF_CONDUCT.md).
