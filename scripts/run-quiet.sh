#!/usr/bin/env bash
set -uo pipefail

LOG_FILE="${1:-build.noindex/build.log}"
shift || true
mkdir -p "$(dirname "$LOG_FILE")"

if [[ $# -eq 0 ]]; then
    echo "Usage: $0 <log-file> <command...>" >&2
    exit 2
fi

echo "▶ Executing: $*"
if "$@" > "$LOG_FILE" 2>&1; then
    echo "✓ Succeeded."
    exit 0
else
    EXIT_CODE=$?
    echo "✗ Failed with exit code $EXIT_CODE. Diagnostic slice:" >&2
    echo "--------------------------------------------------------" >&2
    grep -E -C 2 -i "(error:|fatal error:|BUILD FAILED|\*\*\* TEST FAILED \*\*\*|Undefined symbols)" "$LOG_FILE" | head -n 40 >&2 || tail -n 25 "$LOG_FILE" >&2
    echo "--------------------------------------------------------" >&2
    echo "Full output captured in: $LOG_FILE" >&2
    exit $EXIT_CODE
fi
