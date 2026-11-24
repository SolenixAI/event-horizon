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
source "${ROOT}/scripts/env.sh" 2>/dev/null || true
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
# Strip .swift extension and target prefixes if supplied by user or agent
TARGET="${TARGET%.swift}"
TARGET="${TARGET#GlimmerTests/}"
TARGET="${TARGET#GlimmerTests.}"

# Resolve bare stem (e.g. SdpCodec) to declared test suite (SdpCodecTests) if available
if [[ ! "$TARGET" =~ "/" ]] && [[ ! "$TARGET" =~ Tests$ ]]; then
	if [[ -f "${ROOT}/GlimmerTests/${TARGET}Tests.swift" ]]; then
		TARGET="${TARGET}Tests"
	fi
fi

# Verify the suite file exists to prevent Xcode's silent zero-test pass quirk
SUITE="${TARGET%%/*}"
if [[ ! -f "${ROOT}/GlimmerTests/${SUITE}.swift" ]]; then
	echo "Error: Test suite file GlimmerTests/${SUITE}.swift not found." >&2
	exit 1
fi

ARCH="$(uname -m)"
QUIET_FLAG="-quiet"
if [[ "${VERBOSE:-0}" == "1" ]]; then
	QUIET_FLAG=""
fi

echo "▶ Running focused tests: GlimmerTests/${TARGET}..."
mkdir -p "${DERIVED}"

rc=0
if [[ "${VERBOSE:-0}" == "1" ]]; then
	bash "${ROOT}/scripts/generate-build-info.sh"
	xcodebuild test \
		-project "${ROOT}/Glimmer.xcodeproj" \
		-scheme Glimmer \
		-configuration Debug \
		-xcconfig "${STREAM_XCCONFIG}" \
		CODE_SIGNING_ALLOWED=NO \
		-derivedDataPath "${DERIVED}" \
		-destination "platform=macOS,arch=${ARCH}" \
		-only-testing:"GlimmerTests/${TARGET}" || rc=$?
else
	bash "${ROOT}/scripts/generate-build-info.sh" >/dev/null 2>&1 || true
	TEST_LOG="${DERIVED}/test-unit-${SUITE}.log"
	if ! xcodebuild test \
		-project "${ROOT}/Glimmer.xcodeproj" \
		-scheme Glimmer \
		-configuration Debug \
		-xcconfig "${STREAM_XCCONFIG}" \
		CODE_SIGNING_ALLOWED=NO \
		-derivedDataPath "${DERIVED}" \
		-destination "platform=macOS,arch=${ARCH}" \
		-quiet \
		-only-testing:"GlimmerTests/${TARGET}" > "${TEST_LOG}" 2>&1; then
		rc=$?
	fi
fi

# Unregister debug bundle from LaunchServices so dev builds stay out of Spotlight
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister \
	-u "${DERIVED}/Build/Products/Debug/Event Horizon.app" 2>/dev/null || true

if [[ $rc -eq 0 ]]; then
	echo "✓ GlimmerTests/${TARGET} passed."
else
	if [[ -n "${TEST_LOG:-}" && -f "${TEST_LOG}" ]]; then
		echo "✗ GlimmerTests/${TARGET} failed with exit code $rc. Diagnostic slice:" >&2
		echo "--------------------------------------------------------" >&2
		grep -E -C 2 -i "(error:|fatal error:|BUILD FAILED|\*\*\* TEST FAILED \*\*\*|Undefined symbols)" "${TEST_LOG}" | head -n 40 >&2 || tail -n 25 "${TEST_LOG}" >&2
		echo "--------------------------------------------------------" >&2
		echo "Full output captured in: ${TEST_LOG}" >&2
	else
		echo "✗ GlimmerTests/${TARGET} failed with exit code $rc." >&2
	fi
fi

exit $rc
