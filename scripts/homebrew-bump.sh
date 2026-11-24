#!/bin/bash
#
# homebrew-bump.sh - trigger a Homebrew cask update in SolenixAI/homebrew-tap
# for a published Event Horizon release.
#
# Package distribution is decoupled to the external tap repository:
#   https://github.com/SolenixAI/homebrew-tap
#
# This script sends a repository_dispatch event ("app-release") with the target
# release version payload to SolenixAI/homebrew-tap.
#
# Usage:  scripts/homebrew-bump.sh [version]     # default: Glimmer/Version.xcconfig
# Environment:
#   TAP_REPO            Target tap repository (default: SolenixAI/homebrew-tap)
#   HOMEBREW_TAP_TOKEN  Personal access token with repo scope for the tap (optional, falls back to GH_TOKEN/gh auth)
set -euo pipefail

HERE="$(cd "$(dirname "$0")/.." && pwd)"
VERSION="${1:-$(sed -n 's/^MARKETING_VERSION = \(.*\)/\1/p' "$HERE/Glimmer/Version.xcconfig" | tr -d ' ')}"
TAP_REPO="${TAP_REPO:-SolenixAI/homebrew-tap}"

[ -n "$VERSION" ] || { echo "ERR: no version given and none found in Glimmer/Version.xcconfig" >&2; exit 1; }

# Prefer HOMEBREW_TAP_TOKEN if set
if [ -n "${HOMEBREW_TAP_TOKEN:-}" ]; then
	export GH_TOKEN="$HOMEBREW_TAP_TOKEN"
fi

echo "▶ Dispatching cask update to $TAP_REPO for $VERSION..."
if gh api "repos/$TAP_REPO/dispatches" \
	-f event_type="app-release" \
	-f client_payload[version]="$VERSION"; then
	echo "✅ Successfully dispatched cask update for $VERSION to $TAP_REPO."
else
	echo "ERR: Failed to dispatch cask update to $TAP_REPO. Ensure gh is authenticated or HOMEBREW_TAP_TOKEN is set." >&2
	exit 1
fi
