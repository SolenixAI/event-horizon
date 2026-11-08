#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/event-horizon-ci-signing-test.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT

export RUNNER_TEMP="$WORK/runner"
export GITHUB_ENV="$WORK/github-env"
export DEVELOPER_ID_NAME='Developer ID Application: Example (TEAMID)'
export DEVELOPER_ID_P12_BASE64='cDEyLWZpeHR1cmU='
export DEVELOPER_ID_P12_PASSWORD='test-only-p12-password'
export NOTARY_KEY_BASE64='bm90YXJ5LWZpeHR1cmU='
export NOTARY_KEY_ID='test-key-id'
export NOTARY_ISSUER_ID='test-issuer-id'
export SPARKLE_ED_PRIVATE_KEY='test-only-sparkle-key'

bash "$ROOT/scripts/prepare-ci-signing.sh" >/dev/null

python3 - "$GITHUB_ENV" "$RUNNER_TEMP/event-horizon-release" <<'PY'
from pathlib import Path
import stat
import sys

env_file = Path(sys.argv[1]).read_text()
directory = Path(sys.argv[2])
creds_path = next(Path(line.removeprefix("SIGNING_CREDS=")) for line in env_file.splitlines()
                  if line.startswith("SIGNING_CREDS="))
assert "SIGN_KEYCHAIN=" in env_file
assert "DEVELOPER_ID=Developer ID Application: Example (TEAMID)" in env_file
assert "test-only-sparkle-key" in env_file
assert stat.S_IMODE(directory.stat().st_mode) == 0o700
for path in (directory / "developer-id.p12", directory / "notary-key.p8", creds_path):
    assert path.is_file()
    assert stat.S_IMODE(path.stat().st_mode) == 0o600
assert (directory / "developer-id.p12").read_bytes() == b"p12-fixture"
assert (directory / "notary-key.p8").read_bytes() == b"notary-fixture"
credentials = creds_path.read_text()
assert "P12_PASSWORD=test-only-p12-password" in credentials
assert "NOTARY_KEY_ID=test-key-id" in credentials
assert "NOTARY_ISSUER_ID=test-issuer-id" in credentials
PY

echo "PASS: CI signing secrets are decoded into private runner files and action environment"
