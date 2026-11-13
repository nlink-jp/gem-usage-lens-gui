# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/).

## [Unreleased]

### Added

- **This month's consumption in the popover.** Vertex AI bills per calendar
  month, but the month's running total was shown only as part of the budget
  monitor. A **This month** row now shows the cost and billed tokens since
  the 1st whether or not a budget is set. When the budget watches cost, its
  own section already prints the figure and the row is left out.
- **A Month mode for the menu bar**: this calendar month's cost so far,
  beside the modes that show today.
- **This month and a cumulative series in the analysis window.** The period
  picker gains **This month** (since the 1st), and the day-by-day chart can
  be switched from **Daily** to **Cumulative** — the running total, also
  stackable by model. For This month, the monthly budget is drawn across the
  cumulative chart as a line when it is measured in what the chart plots.

### Changed

- The menu-bar mode that shows the budget remaining is now labelled **Left**
  (was **Monthly**), to tell it apart from **Month**. A stored choice keeps
  its meaning.

## [0.1.9] - 2026-11-11

### Changed

- **Bundles gem-usage-lens v0.2.3**, which prices Gemini 4 Carbon
  (`gemini-4-carbon`, $2 / $10 per 1M tokens, promotional through 2026-11-30)
  and corrects Gemini 4 Argon's cached input, which was priced at twice the
  pricing page's figure ($0.20 instead of $0.10 per 1M tokens). Carbon calls
  recorded before this update show as unpriced; press **Reprice** on the badge
  once to price them. The Argon correction raises no badge — the calls were
  priced, only too high — so run `gem-usage-lens reprice` once to apply it to
  the history already stored; new calls are priced correctly either way. See
  the CLI's CHANGELOG.

## [0.1.8] - 2026-11-04

### Changed

- **Bundles gem-usage-lens v0.2.2.** Its config file is now read by
  nlink-jp/toml instead of the third-party `BurntSushi/toml`; it reads as
  before, unknown keys still refused with the CLI's own message. See the CLI's
  CHANGELOG.

## [0.1.7] - 2026-10-14

### Changed

- **Bundles gem-usage-lens v0.2.1**, which prices Gemini 4 Argon
  (`gemini-4-argon`, $2 / $10 per 1M tokens, promotional through 2026-11-30)
  and prices a model id written with Google's publisher qualification
  (`google/gemini-4-argon`) as the model it names. Argon calls recorded
  before this update show as unpriced; press **Reprice** on the badge once to
  price them. The app ingests and reprices with its bundled CLI, so the older
  app would keep recording them at $0.

## [0.1.6] - 2026-09-29

### Changed

- **Bundles gem-usage-lens v0.2.0**, which prices each call at the rate in
  force when it was made. Nothing changes on screen today: no stored cost moves.
  It is the groundwork for the Gemini 3.8 / 3.7 / 3.6 Flash price change Google
  lists for 2027-01-01, which reaches this app only through a later release
  bundling the CLI that adds it — the app ingests and reprices with its bundled
  CLI.

### Fixed

- The release zip no longer carries AppleDouble (`._*`) entries: the app is
  zipped with `ditto --norsrc --noextattr`, so its signature survives unpacking
  with `unzip`. `make verify-release` refuses a zip that carries them.
- **`make verify-release` now pins the bundled CLI to one version.** It already
  refused a missing CLI and a development build, but accepted any clean tag, so an
  app built against an older CLI release passed. `CLI_VERSION` now states the CLI
  this release ships, and the bundled binary must report exactly that tag. `CLI_BIN`
  also finds the CLI's release binary (`dist/<cli>-darwin-arm64`, which is what its
  `make package` leaves) before the development one.

## [0.1.5] - 2026-09-05

Bundles gem-usage-lens v0.1.4, which follows gem-agent ADR-0071 (v0.66.0:
session ids are UUIDs and `/clear` opens a new transcript). The CLI's
parsing needed no change; its `sessions` listing is now chronological with
STARTED / LAST columns, and every `report --json` row carries
`first_record` / `last_record`. The app reads neither the session listing
nor the new keys (unknown keys are ignored on decode), so there is no
app-side change.

## [0.1.4] - 2026-09-03

Bundles gem-usage-lens v0.1.3: `gemini-3.8-flash` (released 2026-09-02) is
priced in the built-in rate table at the same introductory rate as 3.7 / 3.6
Flash, and Grounding with Google Search is charged at the Gemini 3 rate of
$14 per 1,000 Grounding Queries instead of the Gemini 2.x $35. Use
**Reprice** in the popover after updating to apply the new grounding rate to
stored history. No app-side change.

## [0.1.3] - 2026-09-03

Bundles gem-usage-lens v0.1.2: the `tool_prompt` bucket is derived only when
the key is absent from a transcript (written before gem-agent v0.62.0 /
ADR-0066); an explicit value, zero included, is taken as written, so a record
that says zero and does not balance is reported as a checksum mismatch
instead of being re-labelled as derived. The `riskbook_learn` source joins
the known sources. No app-side change.

## [0.1.2] - 2026-09-03

### Added

- **Launch at login** toggle in Settings (General). SMAppService is the source
  of truth: the switch mirrors its status, a change is read back and any
  disagreement (approval pending, not registered, bare binary) is written
  next to the switch with a button to System Settings › Login Items.

## [0.1.1] - 2026-09-03

Bundles gem-usage-lens v0.1.1 (tool-result tokens no longer fail the accounting checksum).

### Added

- The popover's token grid shows a "Tool results" row when built-in tool
  results (search grounding, URL context) were fed back as input
  (`tool_prompt_tokens`, optional in the contract).

## [0.1.0] - 2026-09-03

Initial release — the gem-agent counterpart of claude-usage-lens-gui, bundling
gem-usage-lens v0.1.0.

### Added

- Menu-bar label: today's cost, today's billed tokens, both, or the monthly
  budget remaining with its percent; tinted orange / red by the budget state;
  `⚠︎` while the store holds unpriced calls.
- Popover: today's prompt (with the cached share) / output / thoughts / billed
  tokens, last 30 days, the monthly budget bar with used / left in amount and
  percent, the reset date, a pace forecast line, the running version, and an
  unpriced badge with a Reprice button.
- Analysis window: daily cost or tokens (7 / 30 / 90 days, optionally stacked
  by model), by model, by call source, top projects.
- Settings window: monthly budget on/off, notifications, basis (cost or
  billed tokens), limit, warning / critical thresholds, current state. The
  arithmetic is the CLI's `budget --json`; the app passes settings as flags.
- Notes for calls from pre-ADR-0057 transcripts (lower bound) wherever they
  affect a figure.
- Single-instance guard, App Nap opt-out, `.common`-mode refresh timer,
  foreground notification banners, signed + notarized `.app` with the CLI
  bundled.
