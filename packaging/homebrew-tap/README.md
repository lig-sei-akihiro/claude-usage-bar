# homebrew-tap（配布メモ）

`claude-usage-bar` は Homebrew Cask で配っています。cask 本体（`Casks/claude-usage-bar.rb`）は
**別リポジトリ** `lig-sei-akihiro/homebrew-tap`（`homebrew-` プレフィックス必須 → tap 名は
`lig-sei-akihiro/tap`）に置いてあり、そこが唯一の正本です。このディレクトリは
その配布に関するドキュメント専用で、cask ファイルは持ちません（重複すると
ドリフトの原因になるため削除しました）。

tap リポも source リポも **public** なので、利用者側に GitHub 認証や
`brew trust`、明示的な tap URL は要りません。

## 利用者：インストール手順

tap は自動で追加されるので一行で済みます（fully-qualified 名を指定すると
Homebrew が cask と判別して自動 tap ＋自動 trust する）。

```bash
brew install lig-sei-akihiro/tap/claude-usage-bar
```

tap を明示するなら次の二行でも同じです。

```bash
brew tap lig-sei-akihiro/tap
brew install --cask claude-usage-bar
```

更新: `brew upgrade --cask claude-usage-bar`
アンインストール: `brew uninstall --cask claude-usage-bar`（設定も消すなら `--zap`）

## 管理者：リリース手順

```bash
# 1. .app + zip を作る（release ビルド + ad-hoc 署名）
./Scripts/package_app.sh
#    → dist/ClaudeUsageBar-<version>.zip と sha256 が表示される

# 2. source リポの Release に zip を上げる
gh release create vX.Y.Z dist/ClaudeUsageBar-X.Y.Z.zip \
  --repo lig-sei-akihiro/claude-usage-bar

# 3. tap リポ (lig-sei-akihiro/homebrew-tap) の Casks/claude-usage-bar.rb の
#    version と sha256 を更新して commit/push
```

cask はこのリポではなく tap リポにしか無いので、`version` と `sha256` の更新は
必ず tap リポ側の `Casks/claude-usage-bar.rb` に対して行ってください。
public な Release アセットは静的な URL で取得でき、認証まわりの仕掛けは不要です。

## Gatekeeper に関する注意（2026-09-01〜）

本体は ad-hoc 署名のみ（Apple Developer 契約なし）なので、Homebrew が
ダウンロード時に付ける quarantine 属性のままだと Gatekeeper に弾かれます。
cask の `postflight` で `xattr -dr com.apple.quarantine` を実行して回避しています。

ただし Homebrew は **2026年9月1日で Gatekeeper チェックを通らない cask のサポートを
終了**する方向で、quarantine を剥がす cask は公式 homebrew-cask には入れられません。
そのため自前 tap で配っています。恒久的に「素直に」配りたくなったら Apple Developer
契約（Developer ID 署名 + notarization）に切り替えるのが本筋です。
