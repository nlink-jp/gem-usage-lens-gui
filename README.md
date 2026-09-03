# gem-usage-lens-gui

A macOS menu-bar app that shows today's [gem-agent](https://github.com/nlink-jp/gem-agent)
(Vertex AI Gemini) usage cost, expands into charts, and watches a monthly
budget.

It is a thin front-end over the
[gem-usage-lens](https://github.com/nlink-jp/gem-usage-lens) CLI, which ships
inside the app: the CLI parses the transcripts, prices the tokens and does the
budget arithmetic; the app renders. The counterpart of
[claude-usage-lens-gui](https://github.com/nlink-jp/claude-usage-lens-gui).

> Costs are a Vertex AI **list-price equivalent** (notional), computed from
> gem-agent's own token counts — not your bill.

> macOS releases are **Developer ID signed and Apple-notarized** (stapled).
> They launch without Gatekeeper prompts and work offline.

## Install

Homebrew (macOS 14+, Apple silicon):

```bash
brew install --cask nlink-jp/tap/gem-usage-lens-gui
```

Or download `GemUsageLens.app` from the
[Releases](https://github.com/nlink-jp/gem-usage-lens-gui/releases) page and
drop it into Applications.

Requirements: gem-agent transcripts under `~/.local/state/gem-agent/sessions`.
No credentials, no network. If gem-agent runs with `GEMAGENT_STATE_DIR` set,
the app (launched from Finder, without your shell's environment) will not see
it — point the CLI at the directory with `[sources] sessions_root` in
`~/.config/gem-usage-lens/config.toml` instead.

## What you see

**Menu bar** — today's cost (`$1.47`), today's billed tokens, both, or the
monthly budget remaining (`$98 · 98%`). The label turns orange / red as the
budget crosses its warning / critical thresholds, and carries `⚠︎` while the
store holds calls priced at $0 (see below).

**Popover** (click the item) — today's cost with prompt (and how much of it
was cached), output, thoughts and billed tokens; the last 30 days; the
monthly budget bar with used / left in amount and percent, the reset date and
a pace line ("On pace for $23.81 (24%) by the reset"); the running version;
buttons for Analysis, Settings, Refresh, Quit.

**Analysis window** — daily cost or tokens for the last 7 / 30 / 90 days
(optionally stacked by model), plus cost by model, by call source (main /
risk / compaction / web search …) and by project.

**Settings window** — **Launch at login** (a macOS login item; approve it in System Settings › General › Login Items if asked), then the monthly budget: on/off, notifications, measure by
cost or tokens, the limit, warning / critical percents, and the current state.
The month resets on the 1st at 00:00 local time; there is nothing to
calibrate, since Vertex AI has no rolling quota.

### Unpriced calls

If gem-agent starts using a model the bundled CLI's rate table doesn't know,
those calls are stored at $0 and every figure understates. The popover then
shows an orange badge naming the count and model, with a **Reprice** button:
after updating the app (or pricing the model in the CLI's `config.toml`),
Reprice recomputes the stored history in place.

### Older transcripts

Transcripts written by gem-agent before v0.55 (ADR-0057, 2026-08-30) recorded only the
main loop, not risk or compaction calls. Figures that include them are a
lower bound, and the popover says so.

## Data and privacy

Everything is local. The app runs the bundled CLI, which reads
`~/.local/state/gem-agent/sessions/**/*.jsonl` and writes
`~/Library/Application Support/gem-usage-lens/usage.db`. Budget settings are
stored in the app's UserDefaults. Nothing is sent anywhere.

## Build

```bash
make build-app    # signed .app with the CLI bundled (CLI_BIN=../gem-usage-lens/dist/gem-usage-lens)
make package      # notarize + staple + zip
make test
```

The CLI must be built first (`make build` in gem-usage-lens); for a release,
build it at its tag with an explicit `VERSION=vX.Y.Z` so the bundled
`--version` is clean.

## Documents

- [Getting started](docs/en/getting-started.md) · [日本語](docs/ja/getting-started.ja.md)
- CLI (data backend, JSON contract, pricing): https://github.com/nlink-jp/gem-usage-lens

## License

MIT
