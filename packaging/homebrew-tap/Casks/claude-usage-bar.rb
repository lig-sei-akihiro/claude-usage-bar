cask "claude-usage-bar" do
  version "0.1.0"
  sha256 "REPLACE_WITH_ZIP_SHA256" # `shasum -a 256 dist/ClaudeUsageBar-<version>.zip`

  # Private release asset. Resolve the API asset URL and authenticate with
  # Homebrew's built-in credential helper (keychain / `gh` CLI /
  # HOMEBREW_GITHUB_API_TOKEN — whichever the consumer already has). A private
  # asset's browser download URL does not work; the API asset URL with an
  # "Accept: application/octet-stream" header does.
  #
  # NOTE: `url do` blocks are deprecated in current Homebrew (no replacement), so
  # the URL is computed in a method and passed to a static `url`. This is evaluated
  # at load time, so any `brew` command on this cask makes an authenticated API call.
  def asset_url
    assets = GitHub.get_release("lig-sei-akihiro", "claude-usage-bar", "v#{version}").fetch("assets")
    asset  = assets.find { |a| a["name"] == "ClaudeUsageBar-#{version}.zip" }
    odie "release asset ClaudeUsageBar-#{version}.zip not found" unless asset
    asset.fetch("url")
  end

  url asset_url,
      header: [
        "Accept: application/octet-stream",
        "Authorization: bearer #{GitHub::API.credentials}",
      ]

  name "Claude Usage Bar"
  desc "Menu bar app showing Claude Code usage across accounts"
  homepage "https://github.com/lig-sei-akihiro/claude-usage-bar"

  # No `depends_on macos:` — the app's Info.plist (LSMinimumSystemVersion 14.0)
  # enforces the minimum at launch. The macOS symbol/comparison forms are brittle
  # on brand-new releases (e.g. exact `:sonoma` excludes Tahoe; the ">= :sonoma"
  # string form is deprecated).

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
