#!/usr/bin/env bash
set -euo pipefail

DMG="${1:?Usage: check-release-dmg.sh /path/to/Event-Horizon.dmg}"
if [[ ! -f "$DMG" ]]; then
  echo "ERR: release disk image does not exist: $DMG" >&2
  exit 1
fi

xcrun stapler validate "$DMG"
spctl --assess --type open --context context:primary-signature --verbose=4 "$DMG"

HERE="$(cd "$(dirname "$0")" && pwd)"
MOUNT="$(mktemp -d -t event-horizon-release-check)"
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
"$HERE/check-release-app.sh" "$MOUNT/Event Horizon.app"
