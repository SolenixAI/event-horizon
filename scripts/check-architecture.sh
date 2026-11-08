#!/usr/bin/env bash
# Keep the companion's host policy independent from operating-system and I/O
# implementations. Adapter modules may depend on these ports; the core may not
# reach back into an adapter or call platform APIs directly.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CORE_FILES=("$ROOT/companion/src/host.rs" "$ROOT/companion/src/ports.rs")
FORBIDDEN='crate::os|std::(process|fs|env|os)::|tokio::net|reqwest::|zbus::|windows_sys::|std::net::Tcp(Stream|Listener)'

if matches="$(rg -n -e "$FORBIDDEN" "${CORE_FILES[@]}" || true)" && [[ -n "$matches" ]]; then
	echo "Architecture violation: companion host policy and ports must not depend on OS or network adapters." >&2
	printf '%s\n' "$matches" >&2
	exit 1
fi

echo "Architecture boundaries passed."

# NativeBackend is infrastructure. Production code may construct it only at
# the app composition point; StreamSession receives the StreamingBackendFactory.
NATIVE_CONSTRUCTORS="$(rg -n 'NativeBackend\s*\(' "$ROOT/Glimmer" || true)"
if [[ "$(printf '%s\n' "$NATIVE_CONSTRUCTORS" | sed '/^$/d' | wc -l | tr -d ' ')" != 1 ]] \
	|| [[ "$NATIVE_CONSTRUCTORS" != *"Glimmer/AppModel+Streaming.swift:"* ]]; then
	echo "Architecture violation: construct NativeBackend only at Glimmer/AppModel+Streaming.swift." >&2
	printf '%s\n' "$NATIVE_CONSTRUCTORS" >&2
	exit 1
fi

echo "Swift streaming backend construction is at the app composition point."
