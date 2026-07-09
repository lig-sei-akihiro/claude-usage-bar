# claude-usage-bar

Claude Code の usage / status に特化した macOS メニューバーアプリ。

`claude-usage-all`（複数アカウントの使用状況を認証単位で一括取得する自作コマンド）のデータ取得ロジックを Swift に移植し、[CodexBar](https://github.com/steipete/CodexBar) のメニューバーアプリ構成（Core ライブラリ + App の分離、ステータスアイテムのタイトル描画、表示項目の細かなトグル）を参考に、Claude Code 専用の軽量ツールとして作り起こしたものです。

## できること

- **メニューバーを開かずに 5 時間枠の残量が分かる**（要件 #4）
  ステータスアイテムのタイトルに、5h セッション枠の「残り %」を常時表示。残量が減ると色（normal → warning → critical）で警告します。
- **複数アカウント対応**（要件 #5）
  `~/.claude*` 配下の各 config dir を列挙し、`claude-usage-all` と同じく **認証（メール）単位**で集約。同一メールを共有する複数フォルダは 1 アカウントにまとめます。
- **表示は設定で自由に切り替え（iStat Menus 風）**（要件 #6）
  バーに出す指標（5h / 週(all) / 週(Fable) / 最も逼迫している枠）、残量 or 使用量、リセットまでのカウントダウン表示、複数アカウント時にどれをバーに出すか（最逼迫 / 特定アカウント固定 / 全部並べる）、更新間隔を設定できます。

## データの取得元

`claude-usage-all` と同じ方式（外部依存ゼロ）:

1. `~/.claude*` のうち `.claude.json` を持つ dir を列挙
2. `.claude.json` の `oauthAccount.emailAddress` からメールを取得
3. Keychain から OAuth トークンを取得
   サービス名 = `"Claude Code-credentials-" + sha256(config dir 絶対パス)[:8]`（既定の `~/.claude` は無印 `"Claude Code-credentials"`）。
   ACL プロンプトを避けるため `security` コマンド経由で読み出します。
4. `GET https://api.anthropic.com/api/oauth/usage`（ヘッダ `anthropic-beta: oauth-2025-04-20` + Bearer）を並列取得
5. `limits[]` を session / weekly_all / weekly_scoped(Fable) にマッピング

> ℹ️ `/usage` API は subscription プランでは**利用率（%）**を返し、絶対トークン数は返しません。そのため「残りトークン」は残り % として表示します。

## アーキテクチャ

- `ClaudeUsageBarCore`（library / AppKit 非依存 → ユニットテスト可）
  - `Models` — `RateWindow` / `AccountUsage` / `UsageSnapshot` / `BarTitle`
  - `DisplaySettings` — バー表示の設定値型
  - `ConfigDiscovery` / `KeychainReader` / `UsageAPIClient` / `UsageService` — データ層
  - `BarTitleFormatter` — snapshot + settings → バータイトル（色つき）
  - `DateFormatting` — JST リセット時刻・カウントダウン
- `ClaudeUsageBar`（executable / macOS）
  - `main` + `AppDelegate` — `.accessory`（Dock アイコンなし）で起動
  - `StatusItemController` — `NSStatusItem` のタイトル描画・更新ループ・ポップオーバー
  - `SettingsStore` — UserDefaults ↔ `DisplaySettings`
  - `PopoverView` / `SettingsView` — SwiftUI（アカウント一覧 / 設定画面）

## ビルド（動作確認は各自で）

```bash
swift build                # コンパイル確認
swift run ClaudeUsageBar   # メニューバーに常駐（Dock アイコンなし）
./Scripts/test.sh          # Core のユニットテスト（22 tests / 3 suites）
```

macOS 14+ / Swift 6 ツールチェーン。外部パッケージ依存はありません（AppKit / SwiftUI / CryptoKit / Security の system framework のみ）。

テストは Swift Testing（`import Testing`）で書かれています。フル Xcode 環境なら `swift test` がそのまま通ります。Command Line Tools のみの環境では SwiftPM が swift-testing ランタイムを自動解決できないため、`./Scripts/test.sh` が CLT 同梱の Testing framework へのパスを補って実行します。

## `.app` を作る

`swift build` が生成するのは素の実行ファイルで、`.app` バンドルではありません。ダブルクリック起動・`/Applications` 配置・ログイン項目登録をしたい場合は:

```bash
./Scripts/package_app.sh        # dist/ClaudeUsageBar.app を生成（release ビルド + ad-hoc 署名）
open dist/ClaudeUsageBar.app    # 起動（メニューバーに常駐 / Dock なし）
```

`Info.plist` に `LSUIElement=true` を入れているため、Finder から起動しても Dock に出ないメニューバー常駐アプリになります。ad-hoc 署名のみで Developer ID 署名／notarization はしていないので、初回起動は右クリック →「開く」で Gatekeeper を通してください。`dist/` は `.gitignore` 対象です。

## クレジット

- データ取得ロジックの元: 自作 `claude-usage-all`
- メニューバーアプリ構成の着想: [CodexBar](https://github.com/steipete/CodexBar)（MIT）

## License

MIT
