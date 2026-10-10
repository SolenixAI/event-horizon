#!/bin/bash
#
# homebrew-bump.sh - point the Homebrew cask at a published Event Horizon release.
# Downloads the release DMG, computes its sha256 from the real bytes, and renders
# Casks/event-horizon.rb at the repo root. That is the file the tap reads:
#   brew tap solenixai/event-horizon https://github.com/SolenixAI/event-horizon
#
# It only edits that file. Commit it on a branch and open a pull request; nothing
# is pushed anywhere else. Run this AFTER the GitHub release exists
# (scripts/publish-release.sh uploads it). `make release-publish` calls it as the
# last step, and `make brew-bump` runs it alone. Safe to re-run: an unchanged
# cask reports "already current".
#
# Usage:  scripts/homebrew-bump.sh [version]     # default: Glimmer/Version.xcconfig
# Override the release repo with RELEASES_REPO. No secrets: gh does the download.
set -euo pipefail

HERE="$(cd "$(dirname "$0")/.." && pwd)"
VERSION="${1:-$(sed -n 's/^MARKETING_VERSION = \(.*\)/\1/p' "$HERE/Glimmer/Version.xcconfig" | tr -d ' ')}"
RELEASES_REPO="${RELEASES_REPO:-SolenixAI/event-horizon}"
CASK="$HERE/Casks/event-horizon.rb"
DMG="Event-Horizon-$VERSION.dmg"

[ -n "$VERSION" ] || { echo "ERR: no version given and none found in Glimmer/Version.xcconfig" >&2; exit 1; }

# The cask pins a sha256, so the release asset must already be published.
gh release view "$VERSION" -R "$RELEASES_REPO" >/dev/null 2>&1 || {
	echo "ERR: release $VERSION not found on $RELEASES_REPO - publish it first ('make release-publish')" >&2; exit 1; }

echo "▶ Downloading $DMG to checksum it..."
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
gh release download "$VERSION" -R "$RELEASES_REPO" -p "$DMG" -D "$TMP" --clobber
SHA="$(shasum -a 256 "$TMP/$DMG" | cut -d' ' -f1)"
echo "  ✓ sha256 $SHA"

# The whole cask is rendered here, so its names cannot drift from the release
# names above. The app, the binary and the zap paths follow the product name
# (Event Horizon), the bundle identifier, and the legacy Glimmer data that
# PR #29 moves on first launch.
cat >"$TMP/event-horizon.rb" <<CASK
cask "event-horizon" do
  version "$VERSION"
  sha256 "$SHA"

  url "https://github.com/$RELEASES_REPO/releases/download/#{version}/Event-Horizon-#{version}.dmg"
  name "Event Horizon"
  desc "Stream games from a PC running Sunshine"
  homepage "https://solenix.dev/"

  livecheck do
    url :url
    strategy :github_latest
  end

  auto_updates true
  depends_on arch: :arm64
  depends_on macos: :tahoe

  app "Event Horizon.app"
  binary "#{appdir}/Event Horizon.app/Contents/MacOS/Event Horizon", target: "event-horizon"

  # The helpers are SMAppService items macOS owns. Removing their launchd jobs on
  # every upgrade left the login item broken, so only zap removes them.
  uninstall quit: "dev.solenix.eventhorizon"

  # Legacy io.ugfugl.Glimmer data is removed too: PR #29 moves it once on first
  # launch, but a copy that was never opened under this name is still on the Mac.
  zap launchctl: [
        "dev.solenix.eventhorizon.helper",
        "dev.solenix.eventhorizon.LoginHelper",
        "io.ugfugl.glimmer.helper",
        "io.ugfugl.Glimmer.LoginHelper",
      ],
      trash:     [
        "~/Library/Application Support/Event Horizon",
        "~/Library/Application Support/Glimmer",
        "~/Library/Caches/dev.solenix.eventhorizon",
        "~/Library/Caches/io.ugfugl.Glimmer",
        "~/Library/Containers/io.ugfugl.Glimmer",
        "~/Library/HTTPStorages/dev.solenix.eventhorizon",
        "~/Library/HTTPStorages/io.ugfugl.Glimmer",
        "~/Library/Logs/Event Horizon",
        "~/Library/Logs/Glimmer",
        "~/Library/Preferences/dev.solenix.eventhorizon.plist",
        "~/Library/Preferences/io.ugfugl.Glimmer.plist",
      ]
end
CASK

# Fail loud rather than writing a cask that does not parse or does not carry
# this release's version and checksum.
ruby -c "$TMP/event-horizon.rb" >/dev/null || { echo "ERR: the rendered cask is not valid Ruby" >&2; exit 1; }
grep -qxF "  version \"$VERSION\"" "$TMP/event-horizon.rb" && grep -qxF "  sha256 \"$SHA\"" "$TMP/event-horizon.rb" || {
	echo "ERR: the rendered cask does not carry version $VERSION and sha256 $SHA" >&2; exit 1; }

mkdir -p "$HERE/Casks"
if [ -f "$CASK" ] && cmp -s "$TMP/event-horizon.rb" "$CASK"; then
	echo "✅ Casks/event-horizon.rb already names $VERSION with this checksum - nothing to change."
	exit 0
fi
cp "$TMP/event-horizon.rb" "$CASK"
echo "✅ Casks/event-horizon.rb now names $VERSION (sha256 $SHA)."
echo "  Commit that file on a branch and open a pull request to publish the cask."
