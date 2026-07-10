# claude-usage-bar

Claude Code の usage / status に特化した macOS メニューバーアプリ。

`claude-usage-all`（複数アカウントの使用状況を認証単位で一括取得する自作コマンド）のデータ取得ロジックを Swift に移植し、[CodexBar](https://github.com/steipete/CodexBar) のメニューバーアプリ構成（Core ライブラリ + App の分離、ステータスアイテムのタイトル描画、表示項目の細かなトグル）を参考に、Claude Code 専用の軽量ツールとして作り起こしたものです。

## できること

- **メニューバーを開かずに 5 時間枠の使用状況が分かる**
  ステータスアイテムに、マスコット **Clawd**（コーラルのドット絵）＋使用率ゲージと、5h セッション枠の「利用した %」を常時表示（`claude-usage-all` と同じ基準）。文字は基本白のまま、**パーセントの数値だけ**が使用量に応じて緑 → オレンジ → 赤に変わり、Clawd 本体とゲージも同じ色で追随します。設定で「残り %」表示にも切り替えられます。
- **複数アカウント対応**
  `~/.claude*` 配下の各 config dir を列挙し、`claude-usage-all` と同じく **認証（メール）単位**で集約。同一メールを共有する複数フォルダは 1 アカウントにまとめます。「All accounts」モードでは、各アカウントをラベル付き・省略なしでメニューバーに **最大 2 段でスタック表示**（小フォント）し、各行のパーセントはその行のアカウント自身の severity で色づけします。
- **リセット時刻／カウントダウンも表示可能**
  設定でバーに、リセットまでの残り時間（`3h12m`）またはリセット時刻（`12:49`）を付記できます（Off も選べます）。
- **表示は設定で自由に切り替え（iStat Menus 風）**
  バーに出す指標（5h / 週(all) / 週(Fable) / 最も逼迫している枠）、残量 or 使用量、%記号・指標ラベルの有無、リセット表示（Off / カウントダウン / 時刻）、複数アカウント時にどれをバーに出すか（最逼迫 / 特定アカウント固定 / 全部並べる）、更新間隔（手動 / 1・2・5・15 分）を設定できます。ログイン時の自動起動もここで切り替えます。

## データの取得元

`claude-usage-all` と同じ方式（外部依存ゼロ）:

1. `~/.claude*` のうち config dir を列挙。カスタム dir（`CLAUDE_CONFIG_DIR=~/.claude_x`）は内部の `~/.claude_x/.claude.json` を、既定の `~/.claude`（多くの人はこちら）はデータ用ディレクトリに `.claude.json` を持たないため **ホーム直下の `~/.claude.json`** を config として扱います。
2. `.claude.json` の `oauthAccount.emailAddress` からメールを取得（既定アカウントはホーム直下のファイルを優先して読む）。メールが取れないフォルダはアカウントとして出しません。
3. Keychain から OAuth トークンを取得
   サービス名 = `"Claude Code-credentials-" + sha256(config dir 絶対パス)[:8]`（既定の `~/.claude` は無印 `"Claude Code-credentials"`）。
   ACL プロンプトを避けるため `security` コマンド経由で読み出します。
4. `GET https://api.anthropic.com/api/oauth/usage`（ヘッダ `anthropic-beta: oauth-2025-04-20` + Bearer）を並列取得。同一メールに複数フォルダがぶら下がる場合は各トークンを順に試し、最初に成功したものを採用します。認証に失敗した（トークンが無い / 401 / 403）フォルダはラベルから外します。
5. `limits[]` を session / weekly_all / weekly_scoped(Fable) にマッピング。

> ℹ️ `/usage` API は subscription プランでは**利用率（%）**を返し、絶対トークン数は返しません。そのため数値は % で表示します（既定は「利用した %」、設定で「残り %」に切替可）。

## アーキテクチャ

- `ClaudeUsageBarCore`（library / AppKit 非依存 → ユニットテスト可）
  - `Models` — `RateWindow` / `AccountUsage` / `UsageSnapshot` / `BarTitle` / `StackedLine`
  - `DisplaySettings` — バー表示の設定値型
  - `ConfigDiscovery` / `KeychainReader` / `UsageAPIClient` / `UsageService` — データ層
  - `BarTitleFormatter` — snapshot + settings → バータイトル（1 行 / スタック行 / 代表使用率）
  - `DateFormatting` — JST リセット時刻・カウントダウン
- `ClaudeUsageBar`（executable / macOS）
  - `main` + `AppDelegate` — `.accessory`（Dock アイコンなし）で起動
  - `StatusItemController` — `NSStatusItem` の描画（Clawd グリフ + 色つきテキスト）・更新ループ・ポップオーバー・設定ウィンドウ
  - `SettingsStore` — UserDefaults ↔ `DisplaySettings`（+ 更新間隔）
  - `PopoverView` / `SettingsView` — SwiftUI（アカウント一覧 / 設定画面）
  - `ClawdGlyph` — メニューバー／ポップオーバー用の Clawd + ゲージをその場で描画
  - `SeverityColor` — UI 全体で共有する severity → 色（緑 / オレンジ / 赤 / グレー）
  - `LoginItem` — `SMAppService` によるログイン項目登録

## ビルド（動作確認は各自で）

```bash
swift build                # コンパイル確認
swift run ClaudeUsageBar   # メニューバーに常駐（Dock アイコンなし）
./Scripts/test.sh          # Core のユニットテスト（33 tests / 3 suites）
```

macOS 14+ / Swift 6 ツールチェーン。外部パッケージ依存はありません（AppKit / SwiftUI / CryptoKit / Security / ServiceManagement の system framework のみ）。

テストは Swift Testing（`import Testing`）で書かれています。フル Xcode 環境なら `swift test` がそのまま通ります。Command Line Tools のみの環境では SwiftPM が swift-testing ランタイムを自動解決できないため、`./Scripts/test.sh` が CLT 同梱の Testing framework へのパスを補って実行します。

## `.app` を作る

`swift build` が生成するのは素の実行ファイルで、`.app` バンドルではありません。ダブルクリック起動・`/Applications` 配置・ログイン項目登録をしたい場合は:

```bash
./Scripts/package_app.sh        # dist/ClaudeUsageBar.app を生成（release ビルド + ad-hoc 署名）
open dist/ClaudeUsageBar.app    # 起動（メニューバーに常駐 / Dock なし）
```

`Info.plist` に `LSUIElement=true` を入れているため、Finder から起動しても Dock に出ないメニューバー常駐アプリになります。`Assets/icon/AppIcon.icns` が存在すればバンドルの `Contents/Resources/` に同梱し、アプリアイコンとして使います。ログイン時の自動起動は `SMAppService`（設定の Launch at login トグル）で登録するため、バンドル化された署名済み `.app` でのみ機能します（`swift run` の素の実行ファイルはバンドルが無いので no-op）。

ad-hoc 署名のみで Developer ID 署名／notarization はしていないので、初回起動は右クリック →「開く」で Gatekeeper を通してください。`dist/` は `.gitignore` 対象です。

## アイコン

Claude Code のマスコット **Clawd**（コーラルのドット絵）と、このアプリの主機能である「使用率」を組み合わせたアイコンです。アプリアイコンとメニューバーのグリフは同じキャラで、ひと目で同じアプリと分かるようにしています。

- **アプリアイコン**（Finder / Dock / `.app`）: ダークな角丸スクエアに Clawd ＋下に使用率ゲージ。`Assets/icon/` に一式:
  - `AppIcon.svg`（採用＝ダーク）/ `AppIcon-dark.svg` / `AppIcon-light.svg`
  - `AppIcon.icns`（`package_app.sh` が `Contents/Resources/` に同梱、`Info.plist` の `CFBundleIconFile`）
  - `AppIcon.iconset/`（16〜512 の @1x/@2x 10 枚）
  - `png/icon_{16,32,64,128,256,512,1024}.png`（ポップオーバー / 設定 / README 用のカラー PNG）
- **メニューバー**: Clawd ＋ 5 セグメントの使用率ゲージを **アプリが実行時に描画**（`ClawdGlyph.swift`）。テンプレート画像ではなく明示色で描き、色は severity 連動（緑 → オレンジ → 赤 → グレー）、ゲージは実使用率の分だけ点灯します。複数アカウント時は、アイコン色とゲージを最も逼迫したアカウントに合わせます。
- **ポップオーバー**: ヘッダのタイトル文字は無く、各アカウント行の先頭に **そのアカウント自身の色・使用率**の Clawd バッジ（`ClawdGlyph.badge`）を表示。更新ボタンとタイムスタンプはフッタにあります。
- **設定画面**: 先頭に `NSApp.applicationIconImage`（＝同梱した `.icns`）とアプリ名を表示。

アプリアイコンの生成（SVG → 全サイズ）:

```bash
python3 Scripts/gen_icon_svg.py   # スプライト/配色から SVG を生成（Assets/icon/AppIcon*.svg）
./Scripts/make_icons.sh           # SVG → iconset / .icns / PNG（要 librsvg: brew install librsvg）
```

メニューバーのグリフはアプリが実行時に描くので、この生成対象には含まれません。ドット絵のスプライトは `Scripts/gen_icon_svg.py`（アプリアイコン）と `ClawdGlyph.swift`（メニューバー）の 2 か所にあり、キャラを変えるときは両方を合わせます。

## クレジット

- データ取得ロジックの元: 自作 `claude-usage-all`
- メニューバーアプリ構成の着想: [CodexBar](https://github.com/steipete/CodexBar)（MIT）

## License

MIT
