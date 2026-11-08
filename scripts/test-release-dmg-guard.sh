#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/event-horizon-dmg-guard.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT
mkdir -p "$WORK/bin"
: > "$WORK/commands.log"
: > "$WORK/Event-Horizon.dmg"

cat > "$WORK/bin/codesign" <<'STUB'
#!/bin/sh
printf 'codesign %s\n' "$*" >> "$COMMAND_LOG"
exit "${CODESIGN_EXIT:-0}"
STUB
cat > "$WORK/bin/xcrun" <<'STUB'
#!/bin/sh
printf 'xcrun %s\n' "$*" >> "$COMMAND_LOG"
case "$*" in
  *Event-Horizon.dmg) exit "${DMG_STAPLER_EXIT:-0}" ;;
  *) exit "${APP_STAPLER_EXIT:-0}" ;;
esac
STUB
cat > "$WORK/bin/spctl" <<'STUB'
#!/bin/sh
printf 'spctl %s\n' "$*" >> "$COMMAND_LOG"
case "$*" in
  *'--type open'*) exit "${DMG_SPCTL_EXIT:-0}" ;;
  *) exit "${APP_SPCTL_EXIT:-0}" ;;
esac
STUB
cat > "$WORK/bin/hdiutil" <<'STUB'
#!/bin/sh
printf 'hdiutil %s\n' "$*" >> "$COMMAND_LOG"
if [ "$1" = attach ]; then
  shift
  while [ "$#" -gt 0 ]; do
    if [ "$1" = -mountpoint ]; then
      shift
      mkdir -p "$1/Event Horizon.app"
      break
    fi
    shift
  done
fi
exit 0
STUB
chmod +x "$WORK/bin/codesign" "$WORK/bin/xcrun" "$WORK/bin/spctl" "$WORK/bin/hdiutil"

run_guard() {
  PATH="$WORK/bin:$PATH" \
    COMMAND_LOG="$WORK/commands.log" \
    DMG_STAPLER_EXIT="${1:-0}" \
    DMG_SPCTL_EXIT="${2:-0}" \
    CODESIGN_EXIT="${3:-0}" \
    APP_STAPLER_EXIT="${4:-0}" \
    APP_SPCTL_EXIT="${5:-0}" \
    bash "$ROOT/scripts/check-release-dmg.sh" "$WORK/Event-Horizon.dmg"
}

if run_guard 1 0 0 0 0 >/dev/null 2>&1; then
  echo "FAIL: DMG guard accepted a missing notarization ticket" >&2
  exit 1
fi
if grep -q '^hdiutil ' "$WORK/commands.log"; then
  echo "FAIL: DMG was mounted before stapler validation passed" >&2
  exit 1
fi

: > "$WORK/commands.log"
if run_guard 0 1 0 0 0 >/dev/null 2>&1; then
  echo "FAIL: DMG guard accepted a Gatekeeper rejection" >&2
  exit 1
fi
if grep -q '^hdiutil ' "$WORK/commands.log"; then
  echo "FAIL: DMG was mounted after Gatekeeper rejected it" >&2
  exit 1
fi

: > "$WORK/commands.log"
if run_guard 0 0 1 0 0 >/dev/null 2>&1; then
  echo "FAIL: DMG guard accepted an invalid bundled app" >&2
  exit 1
fi
grep -q '^hdiutil attach ' "$WORK/commands.log"
grep -q '^codesign ' "$WORK/commands.log"

: > "$WORK/commands.log"
run_guard 0 0 0 0 0 >/dev/null
grep -q '^xcrun stapler validate ' "$WORK/commands.log"
grep -q '^spctl --assess --type open ' "$WORK/commands.log"
grep -q '^hdiutil attach ' "$WORK/commands.log"
grep -q '^codesign ' "$WORK/commands.log"
grep -q '^spctl --assess --type execute ' "$WORK/commands.log"
grep -q '^hdiutil detach ' "$WORK/commands.log"

echo "PASS: DMG guard validates its ticket, Gatekeeper result, and bundled app"
