#!/usr/bin/env bash
set -euo pipefail

DMG="${1:?Usage: check-development-release-dmg.sh /path/to/Event-Horizon.dmg}"
[[ -f "$DMG" ]] || { echo "ERR: disk image does not exist: $DMG" >&2; exit 1; }

MOUNT="$(mktemp -d -t event-horizon-dev-release-check)"
ATTACHED=0
cleanup() {
	if [[ "$ATTACHED" = 1 ]]; then
		hdiutil detach "$MOUNT" -quiet -force >/dev/null 2>&1 || true
	fi
	rmdir "$MOUNT" 2>/dev/null || true
}
trap cleanup EXIT

hdiutil attach -readonly -nobrowse -noverify -mountpoint "$MOUNT" "$DMG" >/dev/null
ATTACHED=1
"$(dirname "$0")/check-development-release-app.sh" "$MOUNT/Event Horizon.app"
