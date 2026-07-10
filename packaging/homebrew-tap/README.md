# homebrew-tap（社内配布用スケルトン）

このディレクトリは、`claude-usage-bar` を社内だけに Homebrew Cask で配る private tap
リポジトリの雛形です。実運用では **別リポジトリ** `lig-sei-akihiro/homebrew-tap`
（`homebrew-` プレフィックス必須 → tap 名は `lig-sei-akihiro/tap`）として **private** で作り、
`Casks/claude-usage-bar.rb` をそこへ置きます。

## 前提（この構成の割り切り）

- **署名**: ad-hoc のみ（Apple Developer 契約なし）。cask の `postflight` で
  quarantine 属性を剥がして Gatekeeper を通す。
- **配布**: 完全 private。Release アセットの取得に GitHub 認証が要る。

## 管理者：リリース手順

```bash
# 1. .app + zip を作る（release ビルド + ad-hoc 署名）
./Scripts/package_app.sh
#    → dist/ClaudeUsageBar-<version>.zip と sha256 が表示される

# 2. private な source リポの Release に zip を上げる
gh release create v0.1.0 dist/ClaudeUsageBar-0.1.0.zip \
  --repo lig-sei-akihiro/claude-usage-bar

# 3. tap リポの Casks/claude-usage-bar.rb の version と sha256 を更新して commit/push
```

初回だけ private な tap リポを作成:

```bash
gh repo create lig-sei-akihiro/homebrew-tap --private
# Casks/claude-usage-bar.rb を入れて push
```

## 利用者：インストール手順

cask は Homebrew 組み込みの GitHub 認証ヘルパー（`GitHub::API.credentials`）を使うので、
以下のいずれかで認証情報があれば追加設定は不要:

- `gh auth login` 済み（多くの開発者が該当）
- `export HOMEBREW_GITHUB_API_TOKEN=ghp_xxxxxxxx`（repo スコープ PAT）
- macOS キーチェーンの GitHub 資格情報

```bash
# 1. private tap を SSH で tap（git 認証を使う）
brew tap lig-sei-akihiro/tap git@github.com:lig-sei-akihiro/homebrew-tap.git

# 2. インストール（postflight が quarantine を剥がすので --no-quarantine 不要）
brew install --cask claude-usage-bar
```

更新: `brew upgrade --cask claude-usage-bar`
アンインストール: `brew uninstall --cask claude-usage-bar`（設定も消すなら `--zap`）

## Gatekeeper に関する注意（2026-09-01〜）

Homebrew は **2026年9月1日で Gatekeeper チェックを通らない cask のサポートを終了**し、
`--no-quarantine` フラグも廃止方向。未署名（ad-hoc）アプリはこれに該当するため、
本 cask は `postflight` で `xattr -dr com.apple.quarantine` を実行して回避している。
これは private tap だから自分でルールを決められる前提の割り切りであり、公式
homebrew-cask には出せない。恒久的に「素直に」配りたくなったら Apple Developer 契約
（Developer ID 署名 + notarization）に切り替えるのが本筋。
