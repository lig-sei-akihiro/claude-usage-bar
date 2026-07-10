cask "claude-usage-bar" do
  version "0.1.0"
  sha256 "REPLACE_WITH_ZIP_SHA256" # `shasum -a 256 dist/ClaudeUsageBar-<version>.zip`

  # Private release asset. Resolve it through the GitHub API and authenticate
  # with Homebrew's built-in credential helper (keychain / `gh` CLI /
  # HOMEBREW_GITHUB_API_TOKEN — whichever the consumer already has). Downloading
  # a private release asset by its browser URL does not work; the API asset URL
  # with an octet-stream Accept header does.
  url do
    assets = GitHub.get_release("lig-sei-akihiro", "claude-usage-bar", "v#{version}").fetch("assets")
    asset  = assets.find { |a| a["name"] == "ClaudeUsageBar-#{version}.zip" }.fetch("url")
    [asset, header: [
      "Accept: application/octet-stream",
      "Authorization: bearer #{GitHub::API.credentials}",
    ]]
  end
  name "Claude Usage Bar"
  desc "Menu bar app showing Claude Code usage across accounts"
  homepage "https://github.com/lig-sei-akihiro/claude-usage-bar"

  depends_on macos: ">= :sonoma" # Info.plist LSMinimumSystemVersion 14.0

  app "ClaudeUsageBar.app"

  # The app is only ad-hoc signed (no Developer ID / notarization), so the
  # quarantine flag Homebrew adds on download would make Gatekeeper block it.
  # Strip it here so `brew install --cask claude-usage-bar` just works —
  # no per-user `--no-quarantine` needed.
  postflight do
    system_command "/usr/bin/xattr",
                   args: ["-dr", "com.apple.quarantine", "#{appdir}/ClaudeUsageBar.app"]
  end

  uninstall quit: "com.lig-sei-akihiro.claude-usage-bar"

  zap trash: "~/Library/Preferences/com.lig-sei-akihiro.claude-usage-bar.plist"
end
