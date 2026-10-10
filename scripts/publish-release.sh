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
TAG="$SHORT"
ASSET_URL="https://github.com/$REPO/releases/download/$TAG/Event-Horizon-$SHORT.zip"
WORK="$(mktemp -d -t event-horizon-publish)"
trap 'rm -rf "$WORK"' EXIT
APPCAST="$WORK/appcast.xml"
NOTES="$WORK/notes.md"

[ -d "$APP" ] || { echo "ERR: app bundle not found at $APP - run via 'make release-publish'" >&2; exit 1; }
if [ -z "${SPARKLE_ED_PRIVATE_KEY:-}" ] && ! "$TOOLS/generate_keys" -p >/dev/null 2>&1; then
	echo "ERR: no EdDSA key in the login keychain - run 'make sparkle-keys' once" >&2; exit 1
fi

# The release tag is the GPL source of this build, so it must be the commit we built:
# require local HEAD == origin/event-horizon (the default branch) before tagging.
git -C "$HERE" fetch --quiet origin event-horizon
HEAD_SHA="$(git -C "$HERE" rev-parse HEAD)"
BASE_SHA="$(git -C "$HERE" rev-parse origin/event-horizon)"
[ "$HEAD_SHA" = "$BASE_SHA" ] || {
	echo "ERR: local HEAD ($HEAD_SHA) != origin/event-horizon ($BASE_SHA)." >&2
	echo "  Merge the change, then 'git pull --ff-only' before publishing - the release tag" >&2
	echo "  is the GPLv3 source and must match the built commit." >&2
	exit 1
}

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

# Release notes: this version's CHANGELOG.md section, the same text the appcast
# <description> carries, so the GitHub release and Sparkle's "what's new" never disagree.
if "$HERE/scripts/changelog.py" --version "$SHORT" --changelog "$HERE/CHANGELOG.md" >"$NOTES" 2>/dev/null \
	&& [ -s "$NOTES" ]; then
	echo "  ✓ release notes from CHANGELOG.md ($(wc -l <"$NOTES" | tr -d ' ') lines)"
else
	echo "  ! no '## $SHORT' section in CHANGELOG.md - using boilerplate release notes" >&2
	printf 'Event Horizon %s. Auto-updates via Sparkle.\n' "$SHORT" >"$NOTES"
fi
printf '\nSource: this repo at tag %s (GPLv3).\n' "$TAG" >>"$NOTES"

echo "Publishing GitHub release ${TAG} to ${REPO}"
ASSETS=("$ZIP")
[ -f "$DMG" ] && ASSETS+=("$DMG")
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

echo "▶ Adding the item to appcast.xml..."
"$HERE/scripts/update-appcast.py" "$APPCAST" \
	--short-version "$SHORT" --version "$BUILD" \
	--url "$ASSET_URL" --ed-signature "$ED_SIG" --length "$LENGTH" --min-system 26.0 \
	--changelog "$HERE/CHANGELOG.md"
gh release upload "$TAG" "$APPCAST" -R "$REPO" --clobber
gh release edit "$TAG" -R "$REPO" --draft=false
echo "  ✓ release published with appcast.xml"

echo "✅ Published Event Horizon $SHORT - Sparkle clients see it within a day (or now via Check for Updates…)."
