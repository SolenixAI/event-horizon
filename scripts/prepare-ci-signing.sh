#!/usr/bin/env bash
# Materialize protected release secrets into the runner's private temp directory.
set -euo pipefail

require_secret() {
	local name="$1"
	[[ -n "${!name:-}" ]] || { echo "ERR: required release secret $name is missing" >&2; exit 1; }
}

for name in DEVELOPER_ID_NAME DEVELOPER_ID_P12_BASE64 DEVELOPER_ID_P12_PASSWORD \
	NOTARY_KEY_BASE64 NOTARY_KEY_ID NOTARY_ISSUER_ID SPARKLE_ED_PRIVATE_KEY; do
	require_secret "$name"
done

[[ -n "${RUNNER_TEMP:-}" && -n "${GITHUB_ENV:-}" ]] || {
	echo "ERR: this script must run in a GitHub Actions job" >&2
	exit 1
}

umask 077
creds_dir="$RUNNER_TEMP/event-horizon-release"
mkdir -p "$creds_dir"
chmod 700 "$creds_dir"
p12="$creds_dir/developer-id.p12"
notary_key="$creds_dir/notary-key.p8"
creds="$creds_dir/signing.env"
keychain="$creds_dir/signing.keychain-db"

decode_base64() {
	python3 -c 'import base64, sys; sys.stdout.buffer.write(base64.b64decode(sys.stdin.buffer.read(), validate=True))'
}

printf '%s' "$DEVELOPER_ID_P12_BASE64" | decode_base64 > "$p12"
printf '%s' "$NOTARY_KEY_BASE64" | decode_base64 > "$notary_key"
[[ -s "$p12" && -s "$notary_key" ]] || { echo "ERR: decoded signing material is empty" >&2; exit 1; }
chmod 600 "$p12" "$notary_key"

keychain_password="$(openssl rand -hex 24)"
cat > "$creds" <<EOF
P12_PATH=$p12
P12_PASSWORD=$DEVELOPER_ID_P12_PASSWORD
NOTARY_KEY_PATH=$notary_key
NOTARY_KEY_ID=$NOTARY_KEY_ID
NOTARY_ISSUER_ID=$NOTARY_ISSUER_ID
SIGN_KEYCHAIN_PASSWORD=$keychain_password
EOF
chmod 600 "$creds"

delimiter="EVENT_HORIZON_$(openssl rand -hex 16)"
{
	printf 'SIGNING_CREDS=%s\n' "$creds"
	printf 'SIGN_KEYCHAIN=%s\n' "$keychain"
	printf 'DEVELOPER_ID=%s\n' "$DEVELOPER_ID_NAME"
	printf 'SPARKLE_ED_PRIVATE_KEY<<%s\n' "$delimiter"
	printf '%s\n' "$SPARKLE_ED_PRIVATE_KEY"
	printf '%s\n' "$delimiter"
} >> "$GITHUB_ENV"

echo "Release signing material is ready in the runner's private temporary directory."
