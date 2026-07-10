# claude-usage-bar

Claude Code の usage をメニューバーに常駐表示する macOS アプリ。データ取得は自作 `claude-usage-all` と同方式、構成は [CodexBar](https://github.com/steipete/CodexBar) を参考にした外部依存ゼロの軽量ツール。

## できること

- **5h セッション枠の使用率をメニューバーに常時表示**。マスコット **Clawd**（ドット絵）＋使用率ゲージ付き。文字は白、**パーセントだけ**が緑 → オレンジ → 赤に変化（Clawd とゲージも追随）。
- **複数アカウント対応**。`~/.claude*` を認証（メール）単位で集約。`~/.claude` だけの既定環境にも対応。
- **iStat Menus 風の細かい設定**。指標（5h / 週 / 最逼迫）・残量/使用量・リセット表示（Off / カウントダウン / 時刻）・アカウント表示モード・更新間隔・ログイン時自動起動。

## 使い方

```bash
swift run ClaudeUsageBar        # メニューバーに常駐（Dock なし）
./Scripts/test.sh               # Core のユニットテスト
./Scripts/package_app.sh        # dist/ClaudeUsageBar.app を生成（release + ad-hoc 署名）
```

macOS 14+ / Swift 6。外部パッケージ依存なし（AppKit / SwiftUI / CryptoKit / Security / ServiceManagement のみ）。ad-hoc 署名のため初回は右クリック →「開く」で Gatekeeper を通してください。

アプリアイコンは `python3 Scripts/gen_icon_svg.py && ./Scripts/make_icons.sh`（要 `brew install librsvg`）で `Assets/icon/` に再生成。メニューバーのグリフは `ClawdGlyph.swift` が実行時に描画します。

> ℹ️ `/usage` API は subscription プランでは利用率（%）のみを返すため、数値は % 表示です。

## クレジット / License

データ取得: 自作 `claude-usage-all` ／ 構成の着想: [CodexBar](https://github.com/steipete/CodexBar)（MIT）。本体は MIT License。
</content>
