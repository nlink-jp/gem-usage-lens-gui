# CLAUDE.md — gem-usage-lens-gui

**Organization rules (mandatory): https://github.com/nlink-jp/.github/blob/main/CONVENTIONS.md**

## Project overview

macOS menu-bar app that surfaces today's gem-agent (Vertex AI Gemini) usage
cost, expands into graphical analysis, and monitors a calendar-month budget.
Native SwiftUI front-end over the `gem-usage-lens` CLI (the CLI does parsing /
pricing / aggregation / budget maths; this app invokes it via `--json` and
renders with Swift Charts). `LSUIElement` menu-bar agent, macOS 14+.

## Non-negotiable rules

- **Tests are mandatory** — write them with the implementation
- **Never build ad-hoc** — use `make build` / `make build-app`
- **Docs in sync** — update `README.md` and `README.ja.md` together
- **Small, typed commits** — `feat:`, `fix:`, `test:`, `chore:`, `docs:`, etc.
- **No secrets / PII committed** — the app reads local usage via the CLI only

## Build & test

```sh
make run          # swift run (debug)
make build-app    # signed .app (embeds the CLI)
make package      # notarized + stapled + zipped .app
make test
```

## Key decisions

- **Native SwiftUI** (MenuBarExtra), same pipeline as claude-usage-lens-gui.
- **Data and budget via the CLI's `--json`**, not a reimplementation: the CLI
  is the single source of truth; `Models.swift` tracks its JSON schema and
  `BudgetSettings.cliArguments` is the settings → flags contract.
- **Monthly, uncalibrated budget**: Vertex AI has no rolling quota, so there
  is no calibration UI; the month resets on the 1st at 00:00 local.
- **Self-contained `.app`**: `make build-app` bundles the CLI (signed via `--deep`).

## Architecture

- `Entry.swift` — `@main`; single-instance guard, then `GemUsageLensApp.main()`
- `App.swift` — `MenuBarExtra(.window)` live label + analysis / settings `Window`s
- `UsageModel` — timer-driven `ingest` + summaries + `budget`; on-demand analysis
- `CLIRunner` — locate + run the CLI, decode JSON
- `Models` — `Row` / `Summary` / `BudgetStatus` Codable (match the CLI)
- `PopoverView` / `AnalysisView` / `SettingsView`

## Design references

- CLI (data backend + cost model): https://github.com/nlink-jp/gem-usage-lens
