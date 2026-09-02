# はじめに

## 1. インストール

```bash
brew install --cask nlink-jp/tap/gem-usage-lens-gui
```

または Releases ページから `GemUsageLens.app` を取得してアプリケーションフォルダに
移動します。`gem-usage-lens` CLI はアプリに同梱されているので、別途インストールは
不要です。

## 2. 起動

GemUsageLens を開くと、数秒でメニューバーに `$` の数字が現れます。これが Vertex AI
定価換算の本日の gem-agent コストです。`…` は初回の更新中、`—` は CLI を実行できなかった
ことを表します（アイテムをクリックすると理由が読めます）。

この Mac で gem-agent を一度も実行していなければ、読むべき transcript が無い旨を
ポップオーバーが表示します。

## 3. メニューバーの表示を選ぶ

アイテムをクリックし、**Menu bar** のピッカーで Price / Tokens / Both / Monthly
（予算残量。例: `$98 · 98%`）を選びます。

## 4. 月次予算を設定する

**Settings…** をクリック:

1. **Monitor monthly budget** を ON にします。初回は macOS が通知の許可を求めます。
   しきい値を越えたときにバナーが欲しければ許可してください。
2. **Measure by** で基準（ドルか課金トークンか）を選び、暦月 1 か月の上限を入力します。
3. 警告 / 危険の %（既定 80 / 95）を必要に応じて調整します。

**Current** 節に今月の使用量、残り、リセット日（毎月 1 日 0:00 ローカル）、ペース行が
出ます。メニューバーの表示は警告しきい値で橙、危険しきい値で赤になります。

## 5. 深掘りする

**Analysis…** を開くと、直近 7 / 30 / 90 日の日次推移（**By model** でモデル別積み上げ）、
モデル別・呼び出し種別・プロジェクト別のコストが見られます。棒にカーソルを合わせると
正確な値が出ます。

## 数字の意味

- **Prompt / cached** — prompt トークン数と、そのうち Gemini のキャッシュから供給された
  分（prompt の内数で、追加のトークンではありません）。
- **Output / Thoughts** — 回答トークンと思考トークン。どちらも出力単価で課金されます。
- **Billed** — prompt + output + thoughts。
- コストは global エンドポイントの Vertex AI 定価をこの数に掛けたもの（web 検索には
  リクエスト単位のグラウンディング料金を加算）で、請求額ではなく換算値です。
- メニューバーの `⚠︎` は、同梱の単価表が知らないモデルの呼び出しが $0 で保存されている
  印です。ポップオーバーがそれを名指しし、**Reprice** を提供します。アプリを更新した後に
  押してください。
- "from older gem-agent transcripts — figures are a lower bound" は、gem-agent v0.55（2026-08-30）
  以前の transcript が集計に含まれるときに出ます。当時のファイルは risk / compaction の
  呼び出しを記録していません。

## データの場所

- transcript: `~/.local/state/gem-agent/sessions/`
- store: `~/Library/Application Support/gem-usage-lens/usage.db`
- 設定: アプリの UserDefaults

すべてこの Mac の中に留まります。
