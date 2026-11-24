#!/usr/bin/env bash
# Run targeted Glimmer unit tests quickly without executing the full 1,244-test suite.
#
# Usage:
#   scripts/test-unit.sh <TestSuiteOrTestCase>
#   scripts/test-unit.sh SdpCodecTests
#   scripts/test-unit.sh PairingCryptoTests
#
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DERIVED="${ROOT}/build.noindex"
STREAM_XCCONFIG="${ROOT}/Glimmer/StreamLib.xcconfig"

if [[ $# -eq 0 ]]; then
	echo "Usage: $0 <TestSuiteOrTestCase>" >&2
	echo "Examples:" >&2
	echo "  $0 SdpCodecTests" >&2
	echo "  $0 PairingCryptoTests" >&2
	echo "  $0 OpusDecoderTests" >&2
	exit 2
fi

TARGET="$1"
# Strip leading target/suite prefixes if supplied by user
TARGET="${TARGET#GlimmerTests/}"
TARGET="${TARGET#GlimmerTests.}"

echo "▶ Running focused tests: GlimmerTests/${TARGET}..."
bash "${ROOT}/scripts/generate-build-info.sh"

rc=0
xcodebuild test \
	-project "${ROOT}/Glimmer.xcodeproj" \
	-scheme Glimmer \
	-configuration Debug \
	-xcconfig "${STREAM_XCCONFIG}" \
	CODE_SIGNING_ALLOWED=NO \
	-derivedDataPath "${DERIVED}" \
	-destination 'platform=macOS' \
	-only-testing:"GlimmerTests/${TARGET}" || rc=$?

# Unregister debug bundle from LaunchServices so dev builds stay out of Spotlight
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister \
	-u "${DERIVED}/Build/Products/Debug/Event Horizon.app" 2>/dev/null || true

if [[ $rc -eq 0 ]]; then
	echo "✓ GlimmerTests/${TARGET} passed."
else
	echo "✗ GlimmerTests/${TARGET} failed with exit code $rc." >&2
fi

exit $rc
