# AGENTS.md — gem-usage-lens-gui

## What this is

A macOS menu-bar app (SwiftUI, `MenuBarExtra`, `LSUIElement`) that shows
today's gem-agent (Vertex AI Gemini) usage cost, expands into charts, and
monitors a calendar-month budget. A thin front-end over the `gem-usage-lens`
CLI — the CLI owns parsing / pricing / aggregation / budget arithmetic; this
app only invokes it (`--json`) and renders. macOS 14+. Forked from
`claude-usage-lens-gui`; the differences are the JSON contract, the monthly
(not weekly, not calibrated) budget, and the token vocabulary.

## Build & test

```sh
make run        # swift run (debug)
make build      # swift build -c release
make build-app  # signed .app (embeds the CLI from $CLI_BIN into Resources)
make package    # build-app + notarize + staple + zip
make verify-release  # gate: .notarized marker + stapler validate + bundled CLI version
make test       # swift test
```

## Structure

```
Sources/GemUsageLens/
  Entry.swift        @main; single-instance guard, then GemUsageLensApp.main()
  SingleInstance.swift singleInstanceDecision() — pure startup duplicate guard
  App.swift          MenuBarExtra live label (tinted by budget state) + Window("analysis") + Window("settings")
  UsageModel.swift   ObservableObject; timer → ingest + summaries + budget; loadAnalysis(); notifications
  CLIRunner.swift    locate + run the CLI, decode JSON (CLIJSON.decoder for RFC 3339 dates)
  Models.swift       Codable Row / Summary / BudgetStatus (match the CLI's --json)
  MenuBarMode.swift  price / tokens / both / monthly
  Settings.swift     UserDefaults keys + BudgetSettings snapshot → CLI `budget` flags
  AppVersion.swift   the build's version for display (pure fallback rule)
  PopoverView.swift  today + last 30 + unpriced badge + monthly bar + pace
  AnalysisView.swift Swift Charts: daily / stacked by model / by model / by source / top projects
  SettingsView.swift monthly-budget Form
Info.plist           LSUIElement, LSMultipleInstancesProhibited
scripts/             codesign-darwin-app.sh, notarize-darwin-app.sh, make-icns.sh, brew helpers
assets/              AppIcon-1024.png (→ AppIcon.icns at build)
```

## Gotchas / conventions

- **CLI is the data source, including the budget.** `BudgetSettings.cliArguments`
  turns the UserDefaults into `budget --limit-usd/--limit-tokens/--warn/--critical
  --tz local --json`; `BudgetStatus` decodes the answer. Nothing here computes a
  window, a percent or a forecast — only `percentPair` (display rounding, same
  rule as the CLI) and label text. If the CLI's `budget --json` changes, change
  `Models.swift` in lockstep (`DecodeTests` pins the shape).
- **Only the chosen basis carries a limit**; the other is passed as 0 so the
  CLI answers `state: "unset"` for it. `BudgetStatus.watched` picks the basis
  with a limit. Two limits at once are not a UI option.
- **Every settings change re-runs the CLI** (`refreshBudget`). It is a
  millisecond process; keeping the arithmetic in one place is worth it.
  Notifications fire only from the periodic refresh on an upward severity
  crossing, once per window (the rank resets when `window_start` changes).
- **JSON dates**: the CLI emits whole-second RFC 3339; `CLIJSON.decoder()`
  also tolerates fractional seconds. Don't use `.iso8601` directly.
- **Token vocabulary**: prompt / cached (a share of prompt, not an addition) /
  output / thoughts / billed (`total_tokens` = prompt + output + thoughts).
  Charts plot `total_tokens`. Never add cached to anything.
- **Partial records**: `partial_records` (summary, rows, budget) count calls
  from pre-ADR-0057 transcripts; `UsageModel.partialLabel` renders the
  lower-bound note in the popover, analysis header and budget section.
- **Finding the CLI** (`CLIRunner.findBinary` → pure `resolveBinary`): bundled
  Resources first (signed/notarized trust anchor), then `/usr/local/bin`,
  `/opt/homebrew/bin`. `$GEM_USAGE_LENS_BIN` and the dev paths are
  `#if DEBUG`-only.
- **Unpriced badge**: `unpriced_records` / `unpriced_models` from the
  **last-30-days** summary drive `⚠︎` on the menu label, the orange popover
  section and the Reprice button (`RepricePhase` names every state). The
  CLI's stderr warning never reaches the app — the JSON field is the contract.
- **Live menu-bar label**: the App holds `UsageModel` as `@StateObject`; the
  refresh `Timer` is registered in `.common` run-loop mode so it keeps ticking
  while a menu / popover is tracked; App Nap is opted out via `beginActivity`.
- **Popover root is `.fixedSize(horizontal: false, vertical: true)`** so
  MenuBarExtra gives it the height it needs instead of squeezing children.
- **Settings / analysis are plain `Window`s**, opened via `openWindow(id:)` +
  `NSApp.activate` — the `Settings` scene doesn't focus reliably for an
  LSUIElement app.
- **Notifications**: permission is requested when the user turns the monitor
  (or notifications) on, not when the first alert would fire; a denial is
  logged to stderr with the System Settings hint. `ForegroundBannerDelegate`
  keeps banners visible while the app is briefly frontmost.
- **Single instance**: `LSMultipleInstancesProhibited` + `singleInstanceDecision`
  in `Entry.main` (before the model exists). To run a `dist/` build, quit the
  installed instance first.
- **Version on screen**: `make build-app` substitutes `git describe` into
  Info.plist; the popover footer prints it verbatim (`AppVersion`).
- **Signing**: `--deep` signs the bundled CLI too. No entitlements needed
  (pure SwiftUI/AppKit). `make verify-release` refuses a bundled CLI whose
  `--version` is not a clean `vX.Y.Z`.

## Design reference

- The CLI (JSON contract, pricing, budget): https://github.com/nlink-jp/gem-usage-lens
- Sibling app (origin of the skeleton): https://github.com/nlink-jp/claude-usage-lens-gui
