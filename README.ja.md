# gem-usage-lens-gui

[gem-agent](https://github.com/nlink-jp/gem-agent)（Vertex AI Gemini）の本日コストを
メニューバーに常駐表示し、展開するとグラフで分析でき、月次予算を監視する macOS
アプリです。

[gem-usage-lens](https://github.com/nlink-jp/gem-usage-lens) CLI の薄いフロントエンドで、
CLI はアプリに同梱されています。transcript の解析・単価計算・予算の算術は CLI が
担当し、アプリは描画だけを行います。
[claude-usage-lens-gui](https://github.com/nlink-jp/claude-usage-lens-gui) の対です。

> コストは gem-agent 自身のトークン数に Vertex AI の**定価を掛けた換算値（notional）**で、
> 請求額ではありません。

> macOS 版は **Developer ID 署名 + Apple notarization 済み**（stapled）です。Gatekeeper の
> 警告なしに起動し、オフラインでも動作します。

## インストール

Homebrew（macOS 14 以降, Apple silicon）:

```bash
brew install --cask nlink-jp/tap/gem-usage-lens-gui
```

または [Releases](https://github.com/nlink-jp/gem-usage-lens-gui/releases) から
`GemUsageLens.app` を取得し、アプリケーションフォルダに置きます。

前提: gem-agent の transcript が `~/.local/state/gem-agent/sessions` にあること。
認証情報・ネットワークは不要です。gem-agent を `GEMAGENT_STATE_DIR` 付きで動かしている
場合、Finder から起動したアプリはシェルの環境変数を見ないので、代わりに
`~/.config/gem-usage-lens/config.toml` の `[sources] sessions_root` でその場所を指定してください。

## 画面

**メニューバー** — 本日のコスト（`$1.47`）、本日の課金トークン数、その両方、または
月次予算の残量（`$98 · 98%`）。予算が警告 / 危険しきい値を越えると橙 / 赤に変わり、
$0 で計上された呼び出しが store にある間は `⚠︎` が付きます（後述）。

**ポップオーバー**（アイテムをクリック） — 本日のコストと prompt（うちキャッシュ分）・
output・thoughts・課金トークン、直近 30 日、月次予算のバー（使用 / 残りを金額と % で）、
リセット日、ペース行（"On pace for $23.81 (24%) by the reset"）、実行中の版数、
Analysis / Settings / Refresh / Quit ボタン。

**分析ウィンドウ** — 直近 7 / 30 / 90 日の日次コストまたはトークン（モデル別積み上げも可）、
モデル別・呼び出し種別（main / risk / compaction / web search …）・プロジェクト別のコスト。

**設定ウィンドウ** — **ログイン時に起動**（macOS のログイン項目。求められたら システム設定 › 一般 › ログイン項目 で承認）、そして月次予算: ON/OFF、通知、基準（コストかトークンか）、上限、
警告 / 危険の %、現在の状態。月は毎月 1 日 0:00（ローカル）にリセットされます。
Vertex AI には窓型のクォータが無いので、校正は不要です。

### 未価格の呼び出し

同梱 CLI の単価表に無いモデルを gem-agent が使い始めると、その呼び出しは $0 で保存され、
すべての数字が過小になります。ポップオーバーは件数とモデルを名指しした橙のバッジと
**Reprice** ボタンを出します。アプリを更新（または CLI の `config.toml` に単価を記入）
した後に Reprice を押すと、蓄積済みの履歴がその場で再計算されます。

### 古い transcript

gem-agent v0.55（ADR-0057、2026-08-30）以前の transcript は main ループしか記録しておらず、risk /
compaction の呼び出しがありません。それを含む数字は下限値であり、ポップオーバーは
その旨を表示します。

## データとプライバシー

すべてローカルです。アプリは同梱 CLI を実行し、CLI が
`~/.local/state/gem-agent/sessions/**/*.jsonl` を読み、
`~/Library/Application Support/gem-usage-lens/usage.db` に書きます。予算設定はアプリの
UserDefaults に保存されます。外部には何も送りません。

## ビルド

```bash
make build-app    # CLI 同梱の署名済み .app（CLI_BIN=../gem-usage-lens/dist/gem-usage-lens）
make package      # notarize + staple + zip
make test
```

先に CLI をビルドしてください（gem-usage-lens で `make build`）。リリース時はタグの
コミットで `VERSION=vX.Y.Z` を明示してビルドし、同梱 CLI の `--version` を正しい版数に
します。

## ドキュメント

- [はじめに](docs/ja/getting-started.ja.md) · [English](docs/en/getting-started.md)
- CLI（データバックエンド・JSON 契約・単価）: https://github.com/nlink-jp/gem-usage-lens

## ライセンス

MIT
