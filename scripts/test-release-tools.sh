#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/event-horizon-release-tools.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT

scripts="$ROOT/scripts"
appcast="$WORK/appcast.xml"
cat > "$appcast" <<'XML'
<?xml version="1.0" encoding="utf-8"?>
<rss xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle" version="2.0">
  <channel><title>Event Horizon</title></channel>
</rss>
XML

"$scripts/update-appcast.py" "$appcast" \
	--short-version 2026.10.8 --version 2026100800 \
	--url https://example.invalid/Event-Horizon-2026.10.8.zip \
	--ed-signature test-signature --length 1234 --min-system 26.0 \
	--changelog "$ROOT/CHANGELOG.md" >/dev/null

"$scripts/check-appcast.py" "$appcast" \
	--short-version 2026.10.8 --version 2026100800 \
	--url https://example.invalid/Event-Horizon-2026.10.8.zip \
	--ed-signature test-signature --length 1234 --min-system 26.0 >/dev/null

if "$scripts/check-appcast.py" "$appcast" \
	--short-version 2026.10.8 --version 2026100800 \
	--url https://example.invalid/wrong.zip \
	--ed-signature test-signature --length 1234 --min-system 26.0 >/dev/null 2>&1; then
	echo "FAIL: appcast validator accepted an incorrect update URL" >&2
	exit 1
fi

"$scripts/changelog.py" --version 2026.10.8 --changelog "$ROOT/CHANGELOG.md" >/dev/null
echo "PASS: release notes and generated update metadata are validated"
