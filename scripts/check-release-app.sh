#!/usr/bin/env bash
set -euo pipefail

APP="${1:?Usage: check-release-app.sh /path/to/Event Horizon.app}"
if [[ ! -d "$APP" ]]; then
  echo "ERR: release app bundle does not exist: $APP" >&2
  exit 1
fi

codesign --verify --deep --strict --verbose=2 "$APP"
xcrun stapler validate "$APP"
spctl --assess --type execute --verbose=4 "$APP"

echo "  ✓ signature, notarization ticket, and Gatekeeper acceptance verified"
