#!/usr/bin/env bash
# File-size and single-responsibility gate for Event Horizon.
#
# Principles (docs/CODING_STANDARDS.md):
#   - One purpose per file, one public export per file.
#   - Target: 100 lines. Warn at WARN_LINES, fail at ERROR_LINES.
#
# Tighten the limits over time as files are split. Run locally:
#   scripts/check-file-sizes.sh
#   WARN_LINES=120 ERROR_LINES=250 scripts/check-file-sizes.sh
#
# Exits 1 if any source file exceeds ERROR_LINES or has more than
# MAX_EXPORTS public top-level declarations.

set -euo pipefail

WARN_LINES="${WARN_LINES:-200}"
ERROR_LINES="${ERROR_LINES:-500}"
MAX_EXPORTS="${MAX_EXPORTS:-3}"

ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
cd "$ROOT"

status=0
warn_count=0
error_count=0

check_file() {
    local file="$1"
    local lines
    lines=$(wc -l < "$file" | tr -d ' ')

    if [ "$lines" -gt "$ERROR_LINES" ]; then
        echo "ERROR  ${lines} lines  (limit ${ERROR_LINES})  $file"
        error_count=$((error_count + 1))
        status=1
    elif [ "$lines" -gt "$WARN_LINES" ]; then
        echo "warn   ${lines} lines  (limit ${WARN_LINES})  $file"
        warn_count=$((warn_count + 1))
    fi
}

count_swift_exports() {
    local count
    count=$(grep -cE '^(public |internal |open |fileprivate )?(class|struct|enum|protocol|actor|func|var|let) ' "$1" 2>/dev/null || true)
    echo "${count:-0}"
}

count_rust_exports() {
    local count
    count=$(grep -cE '^pub (fn|struct|enum|trait|const|type|mod|static) ' "$1" 2>/dev/null || true)
    echo "${count:-0}"
}

check_exports() {
    local file="$1"
    local exports
    case "$file" in
        *.swift) exports=$(count_swift_exports "$file") ;;
        *.rs)    exports=$(count_rust_exports "$file") ;;
        *)       return ;;
    esac
    if [ "$exports" -gt "$MAX_EXPORTS" ]; then
        echo "ERROR  ${exports} exports  (limit ${MAX_EXPORTS})  $file"
        error_count=$((error_count + 1))
        status=1
    fi
}

# --- Swift source ---
while IFS= read -r -d '' file; do
    check_file "$file"
    check_exports "$file"
done < <(find Glimmer GlimmerTests helper LoginHelper \
    -name '*.swift' \
    ! -path '*/BuildInfo.generated.swift' \
    -print0 2>/dev/null)

# --- Rust source ---
while IFS= read -r -d '' file; do
    check_file "$file"
    check_exports "$file"
done < <(find companion/src -name '*.rs' -print0 2>/dev/null)

echo ""
echo "File-size gate: WARN>${WARN_LINES}  ERROR>${ERROR_LINES}  exports≤${MAX_EXPORTS}"
echo "  ${warn_count} warnings, ${error_count} errors"

exit $status
