#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/event-horizon-app-guard.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT
mkdir -p "$WORK/bin" "$WORK/Fixture.app"
: > "$WORK/commands.log"

cat > "$WORK/bin/codesign" <<'STUB'
#!/bin/sh
printf 'codesign %s\n' "$*" >> "$COMMAND_LOG"
exit "${CODESIGN_EXIT:-0}"
STUB
cat > "$WORK/bin/xcrun" <<'STUB'
#!/bin/sh
printf 'xcrun %s\n' "$*" >> "$COMMAND_LOG"
exit "${STAPLER_EXIT:-0}"
STUB
cat > "$WORK/bin/spctl" <<'STUB'
#!/bin/sh
printf 'spctl %s\n' "$*" >> "$COMMAND_LOG"
exit "${SPCTL_EXIT:-0}"
STUB
chmod +x "$WORK/bin/codesign" "$WORK/bin/xcrun" "$WORK/bin/spctl"

run_guard() {
  PATH="$WORK/bin:$PATH" \
    COMMAND_LOG="$WORK/commands.log" \
    CODESIGN_EXIT="${1:-0}" \
    STAPLER_EXIT="${2:-0}" \
    SPCTL_EXIT="${3:-0}" \
    bash "$ROOT/scripts/check-release-app.sh" "$WORK/Fixture.app"
}

if run_guard 1 0 0 >/dev/null 2>&1; then
  echo "FAIL: app guard accepted an invalid signature" >&2
  exit 1
fi
grep -q '^codesign ' "$WORK/commands.log"
if grep -q '^xcrun ' "$WORK/commands.log"; then
  echo "FAIL: stapler ran after signature verification failed" >&2
  exit 1
fi

: > "$WORK/commands.log"
if run_guard 0 1 0 >/dev/null 2>&1; then
  echo "FAIL: app guard accepted a missing notarization ticket" >&2
  exit 1
fi
grep -q '^codesign ' "$WORK/commands.log"
grep -q '^xcrun stapler validate ' "$WORK/commands.log"
if grep -q '^spctl ' "$WORK/commands.log"; then
  echo "FAIL: Gatekeeper ran after stapler validation failed" >&2
  exit 1
fi

: > "$WORK/commands.log"
if run_guard 0 0 1 >/dev/null 2>&1; then
  echo "FAIL: app guard accepted a Gatekeeper rejection" >&2
  exit 1
fi
grep -q '^spctl ' "$WORK/commands.log"

: > "$WORK/commands.log"
run_guard 0 0 0 >/dev/null
grep -q '^codesign ' "$WORK/commands.log"
grep -q '^xcrun stapler validate ' "$WORK/commands.log"
grep -q '^spctl ' "$WORK/commands.log"

echo "PASS: app guard rejects signature, ticket, and Gatekeeper failures"
