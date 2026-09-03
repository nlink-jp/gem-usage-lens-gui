# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/).

## [Unreleased]

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
