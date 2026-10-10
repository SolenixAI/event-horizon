#!/bin/bash
#
# homebrew-bump.sh - point the Homebrew cask at a published Event Horizon release.
# Downloads the release DMG, computes its sha256 from the real bytes, renders the
# whole cask (Casks/event-horizon.rb) from the names in this script, records the
# rename from the old glimmer token, then commits and pushes the tap.
#
# Run this AFTER the GitHub release exists (scripts/publish-release.sh uploads
# it); `make release-publish` calls it as the last step. Safe to re-run: if the
# tap already matches the published DMG it reports "already current" and makes
# no commit.
#
# Usage:  scripts/homebrew-bump.sh [version]     # default: Glimmer/Version.xcconfig
# Override the repos with RELEASES_REPO / TAP_REPO; relocate the tap checkout
# with EVENT_HORIZON_TAP_CACHE. No secrets: gh for the download, git over SSH to push.
set -euo pipefail

HERE="$(cd "$(dirname "$0")/.." && pwd)"
VERSION="${1:-$(sed -n 's/^MARKETING_VERSION = \(.*\)/\1/p' "$HERE/Glimmer/Version.xcconfig" | tr -d ' ')}"
RELEASES_REPO="${RELEASES_REPO:-SolenixAI/event-horizon}"
TAP_REPO="${TAP_REPO:-SolenixAI/homebrew-event-horizon}"
TAP_DIR="${EVENT_HORIZON_TAP_CACHE:-$HOME/.cache/event-horizon/homebrew-event-horizon}"
CASK="Casks/event-horizon.rb"
OLD_CASK="Casks/glimmer.rb"
RENAMES="cask_renames.json"
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

if [ -d "$TAP_DIR/.git" ]; then
	git -C "$TAP_DIR" fetch --quiet origin main
	git -C "$TAP_DIR" reset --quiet --hard origin/main
else
	rm -rf "$TAP_DIR"
	mkdir -p "$(dirname "$TAP_DIR")"
	git clone --quiet "git@github.com:$TAP_REPO.git" "$TAP_DIR"
fi

# The whole cask is rendered here, so its names cannot drift from the release
# names above. The app, the binary and the zap paths follow the product name
# (Event Horizon), the bundle identifier, and the legacy Glimmer data that
# PR #29 moves on first launch.
mkdir -p "$TAP_DIR/Casks"
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
  depends_on macos: ">= :tahoe"

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
cp "$TMP/event-horizon.rb" "$TAP_DIR/$CASK"

# cask_renames.json tells `brew update` and `brew upgrade` that the old token
# now means this cask (Homebrew docs: docs.brew.sh/Rename-A-Formula).
printf '{\n  "glimmer": "event-horizon"\n}\n' >"$TAP_DIR/$RENAMES"
if [ -e "$TAP_DIR/$OLD_CASK" ]; then git -C "$TAP_DIR" rm --quiet -- "$OLD_CASK"; fi

# Fail loud rather than pushing a cask that does not parse or does not carry
# this release's version and checksum.
ruby -c "$TAP_DIR/$CASK" >/dev/null || { echo "ERR: $CASK is not valid Ruby" >&2; exit 1; }
grep -qxF "  version \"$VERSION\"" "$TAP_DIR/$CASK" && grep -qxF "  sha256 \"$SHA\"" "$TAP_DIR/$CASK" || {
	echo "ERR: $CASK does not carry version $VERSION and sha256 $SHA" >&2; exit 1; }

git -C "$TAP_DIR" add -A -- Casks "$RENAMES"
if git -C "$TAP_DIR" diff --cached --quiet; then
	echo "✅ Homebrew cask already current at $VERSION - nothing to push."
	exit 0
fi

git -C "$TAP_DIR" commit --quiet -m "event-horizon $VERSION"
git -C "$TAP_DIR" push --quiet origin HEAD:main
echo "✅ Homebrew cask bumped to $VERSION - 'brew install --cask solenixai/event-horizon/event-horizon'."
