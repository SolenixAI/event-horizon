#!/bin/sh
# Creates "Event Horizon Local Signing", a self-signed code-signing identity in
# the login keychain, for builds on this Mac only. A stable identity means macOS
# keeps Local Network and the other permissions across reinstalls; an adhoc
# signature resets them on every build. Public builds still need Developer ID.
set -eu
NAME="Event Horizon Local Signing"
if security find-identity -p codesigning 2>/dev/null | grep -q "\"$NAME\""; then
  echo "✓ $NAME already exists"; exit 0
fi
dir=$(mktemp -d); trap 'rm -rf "$dir"' EXIT; umask 077
cat > "$dir/cs.cnf" <<CNF
[req]
distinguished_name = dn
prompt = no
x509_extensions = ext
[dn]
CN = $NAME
[ext]
basicConstraints = critical,CA:false
keyUsage = critical,digitalSignature
extendedKeyUsage = critical,codeSigning
CNF
/usr/bin/openssl req -x509 -newkey rsa:2048 -nodes -days 3650 -config "$dir/cs.cnf" \
  -keyout "$dir/key.pem" -out "$dir/cert.pem" 2>/dev/null
pass=$(/usr/bin/openssl rand -hex 16)
/usr/bin/openssl pkcs12 -export -name "$NAME" -inkey "$dir/key.pem" -in "$dir/cert.pem" \
  -out "$dir/cs.p12" -passout "pass:$pass" 2>/dev/null
# -T pre-authorises codesign, so signing never prompts.
security import "$dir/cs.p12" -k "$HOME/Library/Keychains/login.keychain-db" -P "$pass" \
  -T /usr/bin/codesign -T /usr/bin/security >/dev/null
echo "✓ $NAME created; local builds now keep their permissions"
