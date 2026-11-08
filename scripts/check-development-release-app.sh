#!/usr/bin/env bash
set -euo pipefail

APP="${1:?Usage: check-development-release-app.sh /path/to/Event Horizon.app}"
[[ -d "$APP" ]] || { echo "ERR: app bundle does not exist: $APP" >&2; exit 1; }

codesign --verify --deep --strict --verbose=2 "$APP"
DETAILS="$(codesign -dv --verbose=2 "$APP" 2>&1)"
grep -q '^Authority=Apple Development:' <<<"$DETAILS" || {
	echo "ERR: this path requires an Apple Development signature" >&2
	exit 1
}
TEAM="$(sed -n 's/^TeamIdentifier=//p' <<<"$DETAILS" | head -1)"
[[ -n "$TEAM" && "$TEAM" != "not set" ]] || {
	echo "ERR: app signature has no Apple team identifier" >&2
	exit 1
}
codesign -d --entitlements :- "$APP" 2>/dev/null | python3 -c '
import plistlib, sys
entitlements = plistlib.loads(sys.stdin.buffer.read())
if entitlements.get("com.apple.security.cs.disable-library-validation"):
    raise SystemExit("ERR: Release app has library validation disabled")
'

echo "  ✓ valid Apple Development signature (team $TEAM)"
if ASSESSMENT="$(spctl --assess --type execute --verbose=4 "$APP" 2>&1)"; then
	echo "  Gatekeeper accepted this build: $ASSESSMENT"
else
	echo "  Gatekeeper does not accept this non-notarized build: $ASSESSMENT"
	echo "  New installs may require the user to approve it in Privacy & Security."
fi
