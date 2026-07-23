# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

Claude Code の usage をメニューバーに常駐表示する macOS アプリ。Swift Package として実装し、**外部依存はゼロ**（AppKit / SwiftUI / CryptoKit / Security / ServiceManagement のみ）。macOS 14+、Swift 6 ツールチェーン（tools version 5.9）。

## コマンド

```bash
swift build                          # デバッグビルド
swift build -c release               # 最適化ビルド
./Scripts/test.sh                    # Core のユニットテスト（下記の注記を参照）
./Scripts/test.sh --filter UsageParsingTests   # 単一テストスイート（引数はそのまま渡る）
swift run ClaudeUsageBar             # メニューバー常駐で直接実行（Dock アイコンなし）
./Scripts/run_local.sh [debug|release]  # ビルド＋ローカル dist/ アプリをメニューバーに起動し直す
./Scripts/package_app.sh [release|debug] # → dist/ClaudeUsageBar.app（ad-hoc 署名）＋ zip を生成
./Scripts/release.sh <version>       # origin/main に vX.Y.Z タグを打って push（Release ワークフローを起動）
python3 Scripts/gen_icon_svg.py && ./Scripts/make_icons.sh   # アプリアイコン再生成（要 `brew install librsvg`）
```

**テスト:** 素の `swift test` ではなく `./Scripts/test.sh` を使う。テストは swift-testing（`import Testing`）を使い、これは Xcode 16+ に同梱される。Command Line Tools のみの環境では SwiftPM が `Testing` ランタイムを見つけられず `swift test` が *"no such module 'Testing'"* で失敗するため、`test.sh` が CLT の Testing framework を明示指定する。CI はフル Xcode 上で動くのでワークフローは `swift test` を直接呼ぶ。**テストがあるのは `ClaudeUsageBarCore` のみ** — App ターゲットは `run_local.sh` でライト/ダーク両方のメニューバー状態で実起動して確認する。

## アーキテクチャ

**2つのターゲットに意図的に分割:**

- **`ClaudeUsageBarCore`** — 純粋なロジックで **AppKit を import しない**、ユニットテスト可能: 設定探索、Keychain、usage API クライアント、整形、設定の契約。`Models.swift` が AppKit 非依存の値型（`RateWindow`, `AccountUsage`, `UsageSnapshot`, `BarSeverity`, `DisplaySettings`）を持ち、データ層・フォーマッタ・UI 間の共有境界になる。
- **`ClaudeUsageBar`** — 実行ファイル: `NSStatusItem` と、AppKit（`NSHostingController` / `NSHostingView`）経由でホストする SwiftUI ビュー。**SwiftUI の `@main` シーンは無い** — `main.swift` が `NSApplication` を `.accessory`（メニューバー専用・Dock なし）で起動する。

**1回のリフレッシュの流れ**（`StatusItemController` のタイマー → `UsageService.snapshot()`）:

1. `ConfigDiscovery.discover()` が `~/.claude*` の設定ディレクトリを探す。既定アカウントは特別で、`oauthAccount` は `~/.claude/` の中ではなく **ホーム直下の `~/.claude.json`** にある。
2. `KeychainReader.accessToken(forConfigDir:)` が `/usr/bin/security` を shell out で呼ぶ（未署名バイナリからのネイティブな `SecItemCopyMatching` は起動ごとにモーダルプロンプトを出すため）。サービス名は既定ディレクトリが `Claude Code-credentials`、それ以外は `Claude Code-credentials-<sha256(絶対パス)[:8]>`。
3. `UsageAPIClient.fetchWindows()` が `GET https://api.anthropic.com/api/oauth/usage` を呼ぶ。ヘッダ `anthropic-beta: oauth-2025-04-20` が**必須**。`limits[]` を `[RateWindow]` にマップする。subscription プランは利用率（percent）しか返さないため、数値はすべて % 。
4. window は**認証メール単位**で `AccountUsage` にグルーピングされる: 同一メールを共有する複数の設定フォルダは1アカウントに集約、認証できないフォルダはラベルから除外、アカウント全体の取得失敗は throw せず `AccountUsage.error` になる。取得は `TaskGroup` で並行実行。

**UI の状態:** `AppModel`（ObservableObject、`snapshot` と `isRefreshing` を保持）と `SettingsStore`（UserDefaults 永続化、Core の `DisplaySettings` にマップ）。`StatusItemController` がステータスアイテム・リフレッシュタイマー（`SettingsStore.refreshInterval` に連動）・ポップオーバーを所有し、`refresh` / `openSettings` / `quit` のクロージャを `AppModel` に注入することで、SwiftUI ビューがコントローラを直接参照しないようにしている。

## 横断的な不変条件

いずれも「単一の真実の源」であり、1か所を変えるとすべての面が連動して動く（それが意図）:

- **深刻度の閾値:** `BarTitleFormatter.windowSeverity(_:warningAt:criticalAt:)` が、window の percent を深刻度に変換する*唯一*の場所。メニューバーのタイトルもポップオーバーもこれを呼ぶ。返すのは `.normal` / `.warning` / `.critical` のみ; `.stale` / `.error` は window ではなくアカウント単位の状態から来る。
- **深刻度カラー:** `SeverityColor` が*唯一*のパレット（メニューバーのグリフ＋文字、ポップオーバーのバッジ＋バー、閾値スライダー）。**外観適応**で、ライト/ダークで別の値を持つ（標準の `.systemGreen` などはテーマ間でほとんど変化しない）。Radix Colors の "step 11"（アクセシブルなテキスト色）トークンを使用: green → amber → red → grey。
- **メニューバー ≠ システムテーマ:** メニューバーのライト/ダークは壁紙駆動で、システム外観と食い違い得る。そのため `StatusItemController` は深刻度カラーとベースのラベル文字色の両方を、アプリ/システム外観ではなく**ステータスボタンの `effectiveAppearance`** に対して `NSColor.resolved(for:)` で解決する。（ポップオーバーはシステム外観に普通に追従するので、動的カラーをそのまま使う。）
- **グリフ:** `ClawdGlyph` は "Clawd" マスコット＋ミニゲージを、テンプレートではなく明示的な色で、メニューバーの高さに合わせて描画する。スプライトは `Scripts/gen_icon_svg.py`（アプリアイコンの元）と対応しているので、キャラクターを変えるなら両方を同期させること。

## AppKit / SwiftUI の落とし穴（解決済み・再発させない）

- **ポップオーバーのサイズ:** `NSHostingController.sizingOptions = [.preferredContentSize]` でポップオーバーを SwiftUI コンテンツに自動フィットさせる。さもないと NSPopover は既定 320×320 になり、はみ出した内容を黙って切り落とす。
- **使用量バー**は `GeometryReader` ベースではなく `ProgressView(.linear)` を使う — GeometryReader は貪欲で、自動サイズのポップオーバー内でレイアウト再帰の警告を招く。
- **設定ウィンドウ**は `NSHostingView.sizingOptions = []`（固定フレーム）にして、ホスティングビューがウィンドウを画面外へリサイズできないようにする。

## リリースとバージョニング（タグ駆動）

アプリのバージョンは**ツリー内に情報源を持たない** — git タグ由来。`.github/workflows/release.yml` は `v*` タグで起動し、`version = ${tag#v}` を導出、`package_app.sh` に `$VERSION` として渡して `CFBundleShortVersionString` にする。**リリースはファイル編集ではなくタグで上げる**（`./Scripts/release.sh <version>`）。

リリースビルドは ad-hoc 署名で**再現性が無い**（ビルドごとに zip の sha256 が変わる）ため、ワークフローは同一タグの既存リリースを上書きしない（公開済みアセットと Homebrew tap が食い違うため）。やり直すにはリリースとタグを削除して push し直す。成功時は `lig-sei-akihiro/homebrew-tap` の cask の `version` / `sha256` を更新する（`TAP_PUSH_TOKEN` secret が必要）。

**ユニバーサルバイナリ:** `package_app.sh` は Apple Silicon + Intel の両方でネイティブに動く1つの `.app` を作る。各スライスを単一 `--arch` で個別ビルド（SwiftPM ネイティブビルドシステム = Command Line Tools だけで動く）し `lipo` で結合する — 複数 `--arch` を同時指定すると SwiftPM が xcbuild に切り替わり full Xcode を要求するため避けている。`ARCHS` 環境変数で対象アーキを上書き可能（既定 `arm64 x86_64`）。`run_local.sh` はローカル反復を速くするため `ARCHS=$(uname -m)`（ホストアーキのみ）で呼ぶ。

コミットは Conventional Commits（`feat:` / `fix:` / `chore:` / `ci:`）。PR は squash で `main` にマージ。
