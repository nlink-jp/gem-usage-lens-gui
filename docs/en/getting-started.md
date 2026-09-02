# Getting started

## 1. Install

```bash
brew install --cask nlink-jp/tap/gem-usage-lens-gui
```

or download `GemUsageLens.app` from the Releases page and move it to
Applications. The `gem-usage-lens` CLI is inside the app; you do not need to
install it separately.

## 2. Launch

Open GemUsageLens. A `$` figure appears in the menu bar within a few seconds:
today's gem-agent cost at the Vertex AI list price. `…` means the first
refresh is still running; `—` means the CLI could not run (click the item to
read why).

If you have never run gem-agent on this Mac, the popover says so — there are
no transcripts to read yet.

## 3. Choose what the menu bar shows

Click the item and use the **Menu bar** picker: Price, Tokens, Both, or
Monthly (budget remaining, e.g. `$98 · 98%`).

## 4. Set a monthly budget

Click **Settings…**:

1. Turn on **Monitor monthly budget**. macOS asks to allow notifications the
   first time; allow them if you want a banner when a threshold is crossed.
2. Pick **Measure by** — cost in dollars or billed tokens — and enter the
   limit for one calendar month.
3. Adjust the warning / critical percents if 80 / 95 don't suit you.

The **Current** section shows this month's use, what is left, the reset date
(the 1st at 00:00 local time) and the pace line. The menu-bar label turns
orange at the warning threshold and red at the critical one.

## 5. Look deeper

**Analysis…** opens a window with the daily trend for the last 7 / 30 / 90
days (toggle **By model** to stack it), and cost by model, by call source and
by project. Hover a bar for the exact figures.

## What the numbers mean

- **Prompt / cached** — prompt tokens, and how many of them were served from
  Gemini's cache (a discounted share of the prompt, not extra tokens).
- **Output / Thoughts** — answer tokens and thinking tokens; both bill at the
  output price.
- **Billed** — prompt + output + thoughts.
- Costs are the Vertex AI list price on the global endpoint applied to those
  counts (plus a per-request grounding charge for web searches). They are a
  notional figure, not the invoice.
- A `⚠︎` in the menu bar means some calls are stored at $0 because the
  bundled rate table does not know their model. The popover names them and
  offers **Reprice** — use it after updating the app.
- "from older gem-agent transcripts — figures are a lower bound" appears when
  transcripts written before gem-agent v0.57 fall inside a figure; those files
  did not record risk or compaction calls.

## Where the data lives

- Transcripts: `~/.local/state/gem-agent/sessions/`
- Store: `~/Library/Application Support/gem-usage-lens/usage.db`
- Settings: the app's UserDefaults

Everything stays on this Mac.
