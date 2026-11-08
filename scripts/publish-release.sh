#!/bin/bash
#
# publish-release.sh - publish a Sparkle update for a built Event Horizon bundle.
# Called by `make release-publish`, which builds the bundle first.
#
# Steps: ZIP the bundle → EdDSA-sign the ZIP → draft the GitHub release with the ZIP →
# add the new item to the appcast the latest release serves → upload appcast.xml to
# the release → publish it. Info.plist's SUFeedURL reads releases/latest/download/
# appcast.xml, so the feed moves only when the release is published. No Pages, no push.
#
# The EdDSA key comes from the login keychain (`make sparkle-keys`), or from
# SPARKLE_ED_PRIVATE_KEY when a CI runner signs. It never touches the working tree.
#
# Args: <short-version> <build-number> <app-path> <dist-dir> <releases-repo>
set -euo pipefail

SHORT="$1"; BUILD="$2"; APP="$3"; DIST="$4"; REPO="$5"
HERE="$(cd "$(dirname "$0")/.." && pwd)"
TOOLS="$("$HERE/scripts/sparkle-tools.sh")"
# Asset names carry no spaces: GitHub rewrites spaces in uploaded asset names, so
# the name we match and the URL the appcast points at must be the same.
ZIP="$DIST/Event-Horizon-$SHORT.zip"
DMG="$DIST/Event-Horizon-$SHORT.dmg"
CHECKSUMS="$DIST/SHA256SUMS"
TAG="$SHORT"
ASSET_URL="https://github.com/$REPO/releases/download/$TAG/Event-Horizon-$SHORT.zip"
WORK="$(mktemp -d -t event-horizon-publish)"
trap 'rm -rf "$WORK"' EXIT
APPCAST="$WORK/appcast.xml"
NOTES="$WORK/notes.md"

[ -d "$APP" ] || { echo "ERR: app bundle not found at $APP - run via 'make release-publish'" >&2; exit 1; }
[ -f "$DMG" ] || { echo "ERR: DMG not found at $DMG - run via 'make release-publish'" >&2; exit 1; }
"$HERE/scripts/check-release-app.sh" "$APP"
"$HERE/scripts/check-release-dmg.sh" "$DMG"
if [ -z "${SPARKLE_ED_PRIVATE_KEY:-}" ] && ! "$TOOLS/generate_keys" -p >/dev/null 2>&1; then
	echo "ERR: no EdDSA key in the login keychain - run 'make sparkle-keys' once" >&2; exit 1
fi

# The release tag is the GPL source of this build. Require its commit to be on
# the canonical branch before creating or changing a GitHub release.
git -C "$HERE" fetch --quiet origin main
HEAD_SHA="$(git -C "$HERE" rev-parse HEAD)"
if ! git -C "$HERE" merge-base --is-ancestor "$HEAD_SHA" origin/main; then
	echo "ERR: HEAD ($HEAD_SHA) is not on origin/main." >&2
	echo "  Merge the release source into main before publishing." >&2
	exit 1
fi

# Version assertion: the committed version at the tag, the built bundle, and the
# advertised version ($SHORT) must all agree, so the tag's source reproduces the binary.
COMMITTED_VERSION="$(git -C "$HERE" show "HEAD:Glimmer/Version.xcconfig" \
	| sed -n 's/^MARKETING_VERSION = \(.*\)/\1/p' | tr -d ' ')"
BUNDLE_VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' \
	"$APP/Contents/Info.plist" 2>/dev/null || true)"
[ "$COMMITTED_VERSION" = "$SHORT" ] || {
	echo "ERR: committed MARKETING_VERSION ($COMMITTED_VERSION) at HEAD != advertised version ($SHORT)." >&2
	echo "  Bump + commit Version.xcconfig so the tag's source matches what you're publishing." >&2
	exit 1
}
[ "$BUNDLE_VERSION" = "$SHORT" ] || {
	echo "ERR: built bundle CFBundleShortVersionString ($BUNDLE_VERSION) != advertised version ($SHORT)." >&2
	echo "  Rebuild ('make release') from the committed version - the bundle is stale." >&2
	exit 1
}
echo "  ✓ version $SHORT matches committed source AND the built bundle"

echo "▶ Zipping the bundle for Sparkle..."
rm -f "$ZIP"
ditto -c -k --sequesterRsrc --keepParent "$APP" "$ZIP"
(
	cd "$DIST"
	shasum -a 256 "$(basename "$ZIP")" "$(basename "$DMG")" > "$(basename "$CHECKSUMS")"
	shasum -a 256 -c "$(basename "$CHECKSUMS")"
)
echo "  ✓ checksums written to $CHECKSUMS"

echo "▶ EdDSA-signing the update..."
if [ -n "${SPARKLE_ED_PRIVATE_KEY:-}" ]; then
	SIG_LINE="$(printf '%s' "$SPARKLE_ED_PRIVATE_KEY" | "$TOOLS/sign_update" --ed-key-file - "$ZIP")"
else
	SIG_LINE="$("$TOOLS/sign_update" "$ZIP")"
fi
ED_SIG="$(printf '%s' "$SIG_LINE" | sed -n 's/.*sparkle:edSignature="\([^"]*\)".*/\1/p')"
LENGTH="$(printf '%s' "$SIG_LINE" | sed -n 's/.*length="\([^"]*\)".*/\1/p')"
[ -n "$ED_SIG" ] && [ -n "$LENGTH" ] || { echo "ERR: sign_update produced no signature" >&2; exit 1; }
echo "  ✓ signed ($LENGTH bytes)"

# Start from the appcast the latest release serves, so older items stay in the feed.
# A feed that has never been published starts as an empty channel.
LATEST="$(gh release view -R "$REPO" --json tagName -q .tagName 2>/dev/null || true)"
LATEST_ASSETS=""
if [ -n "$LATEST" ]; then
	LATEST_ASSETS="$(gh api "repos/$REPO/releases/tags/$LATEST" --jq '.assets[].name')"
fi
if printf '%s\n' "$LATEST_ASSETS" | grep -qx appcast.xml; then
	gh release download "$LATEST" -R "$REPO" -p appcast.xml -D "$WORK" --clobber
	echo "  ✓ appcast from release $LATEST"
else
	cat >"$APPCAST" <<'XML'
<?xml version="1.0" encoding="utf-8"?>
<rss xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle" version="2.0">
  <channel>
    <title>Event Horizon</title>
  </channel>
</rss>
XML
	echo "  ✓ new appcast (no earlier release carries one)"
fi

# Release notes and Sparkle's update description use the same changelog section.
if ! "$HERE/scripts/changelog.py" --version "$SHORT" --changelog "$HERE/CHANGELOG.md" >"$NOTES"; then
	echo "ERR: add a non-empty '## $SHORT' section to CHANGELOG.md before publishing." >&2
	exit 1
fi
echo "  ✓ release notes from CHANGELOG.md ($(wc -l <"$NOTES" | tr -d ' ') lines)"
printf '\nSource: this repo at tag %s (GPLv3).\n' "$TAG" >>"$NOTES"

echo "▶ Building and validating appcast.xml..."
"$HERE/scripts/update-appcast.py" "$APPCAST" \
	--short-version "$SHORT" --version "$BUILD" \
	--url "$ASSET_URL" --ed-signature "$ED_SIG" --length "$LENGTH" --min-system 26.0 \
	--changelog "$HERE/CHANGELOG.md"
"$HERE/scripts/check-appcast.py" "$APPCAST" \
	--short-version "$SHORT" --version "$BUILD" \
	--url "$ASSET_URL" --ed-signature "$ED_SIG" --length "$LENGTH" --min-system 26.0

echo "Publishing GitHub release ${TAG} to ${REPO}"
ASSETS=("$ZIP" "$DMG" "$CHECKSUMS")
if gh release view "$TAG" -R "$REPO" >/dev/null 2>&1; then
	# A published version is immutable: Sparkle signatures already point at these bytes.
	# A retry may only add a missing asset or confirm an identical one.
	TAG_SHA="$(gh api "repos/$REPO/commits/$TAG" --jq .sha 2>/dev/null || true)"
	[ "$TAG_SHA" = "$HEAD_SHA" ] || {
		echo "ERR: tag $TAG is at ${TAG_SHA:-unknown}, not HEAD ($HEAD_SHA). Published versions are immutable - bump the version." >&2
		exit 1
	}
	for asset in "${ASSETS[@]}"; do
		name="$(basename "$asset")"
		remote="$(gh api "repos/$REPO/releases/tags/$TAG" \
			--jq ".assets[] | select(.name==\"$name\") | .digest // \"unknown\"" 2>/dev/null || true)"
		local_digest="sha256:$(shasum -a 256 "$asset" | cut -d' ' -f1)"
		if [ -z "$remote" ]; then
			gh release upload "$TAG" "$asset" -R "$REPO"
			echo "  ✓ $name added to the existing release"
		elif [ "$remote" = "$local_digest" ]; then
			echo "  = $name already published with these bytes"
		else
			echo "ERR: $name is already published with different bytes ($remote). Published versions are immutable - bump the version." >&2
			exit 1
		fi
	done
else
	# A draft keeps the feed on the previous release until the appcast is uploaded.
	gh release create "$TAG" "${ASSETS[@]}" -R "$REPO" --draft --target "$HEAD_SHA" \
		--title "Event Horizon $SHORT" --notes-file "$NOTES"
fi

echo "▶ Uploading validated appcast.xml..."
gh release upload "$TAG" "$APPCAST" -R "$REPO" --clobber
gh release edit "$TAG" -R "$REPO" --draft=false
echo "  ✓ release published with appcast.xml"

echo "✅ Published Event Horizon $SHORT - Sparkle clients see it within a day (or now via Check for Updates…)."
