#!/usr/bin/env bash
# Keep the companion's host policy independent from operating-system and I/O
# implementations. Adapter modules may depend on these ports; the core may not
# reach back into an adapter or call platform APIs directly.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CORE_FILES=("$ROOT/companion/src/host.rs" "$ROOT/companion/src/ports.rs")
FORBIDDEN='crate::os|std::(process|fs|env|os)::|tokio::net|reqwest::|zbus::|windows_sys::|std::net::Tcp(Stream|Listener)'

matches="$(grep -nE "$FORBIDDEN" "${CORE_FILES[@]}" || true)"
if [[ -n "$matches" ]]; then
	echo "Architecture violation: companion host policy and ports must not depend on OS or network adapters." >&2
	printf '%s\n' "$matches" >&2
	exit 1
fi

echo "Architecture boundaries passed."

# NativeBackend is infrastructure. Production code may construct it only at
# the app composition point; StreamSession receives the StreamingBackendFactory.
NATIVE_CONSTRUCTORS="$(grep -R -nE --include='*.swift' 'NativeBackend[[:space:]]*\(' "$ROOT/Glimmer" || true)"
if [[ "$(printf '%s\n' "$NATIVE_CONSTRUCTORS" | sed '/^$/d' | wc -l | tr -d ' ')" != 1 ]] \
	|| [[ "$NATIVE_CONSTRUCTORS" != *"Glimmer/AppModel+Streaming.swift:"* ]]; then
	echo "Architecture violation: construct NativeBackend only at Glimmer/AppModel+Streaming.swift." >&2
	printf '%s\n' "$NATIVE_CONSTRUCTORS" >&2
	exit 1
fi

echo "Swift streaming backend construction is at the app composition point."

# Control transport in the streaming engine must use ControlTransport (Network.framework
# mutual TLS), deliberately not URLSession (the keychain locks on sleep).
URLSESSION_USES="$(grep -R -nE --include='*.swift' 'URLSession\.(shared|init|[a-zA-Z]+)' "$ROOT/Glimmer/Stream" || true)"
if [[ -n "$URLSESSION_USES" ]]; then
	echo "Architecture violation: Glimmer/Stream must use ControlTransport, not URLSession." >&2
	printf '%s\n' "$URLSESSION_USES" >&2
	exit 1
fi

echo "Swift stream transport uses Network.framework ControlTransport."
