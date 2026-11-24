#!/usr/bin/env bash
#
# update-tower-companion.sh
#
# Helper script to deploy and verify event-horizon-companion updates on zephyr-citadel.
#
set -euo pipefail

# Configuration Defaults
DEFAULT_HOST="192.168.4.157"
DEFAULT_PORT="47970"
DEFAULT_TOKENS_FILE="$HOME/Library/Application Support/Event Horizon/Companion/tokens.json"
UPDATE_COMMAND="cd ~/event-horizon/companion && git pull && cargo build --release && cp target/release/event-horizon-companion ~/.local/bin/ && systemctl --user restart event-horizon-companion.service"

SCHEME="https"
HOST="${COMPANION_HOST:-$DEFAULT_HOST}"
PORT="${COMPANION_PORT:-$DEFAULT_PORT}"
TOKENS_FILE="${TOKENS_FILE:-$DEFAULT_TOKENS_FILE}"
TOKEN="${COMPANION_TOKEN:-}"
MODE="instructions"
SSH_TARGET=""

usage() {
	cat <<EOF
Usage: $(basename "$0") [OPTIONS]

Deployment instructions and verification tool for Event Horizon Tower Companion.

Default mode (no arguments):
  Prints the exact commands to build and restart the companion service on the tower.

Options:
  -c, --check, -v, --verify   Probe https://<host>:<port>/outputs and verify the companion update.
  -s, --ssh [USER@HOST]       Execute the update command remotely via SSH.
      --host <HOST>           Target companion IP or hostname (default: $DEFAULT_HOST or \$COMPANION_HOST).
      --port <PORT>           Target companion port (default: $DEFAULT_PORT or \$COMPANION_PORT).
      --http                  Use plain HTTP instead of HTTPS (for local mock testing).
      --token <TOKEN>         Bearer authentication token (overrides tokens.json or \$COMPANION_TOKEN).
      --tokens-file <PATH>    Path to tokens.json (default: $DEFAULT_TOKENS_FILE).
  -h, --help                  Show this help message.

Examples:
  $(basename "$0")                     # Display tower update command
  $(basename "$0") --verify            # Probe /outputs and confirm display detection
  $(basename "$0") --ssh zephyr-citadel # Run update via SSH and verify
EOF
}

# Parse command line options
while [[ $# -gt 0 ]]; do
	case "$1" in
	-h | --help)
		usage
		exit 0
		;;
	-c | --check | -v | --verify)
		MODE="verify"
		shift
		;;
	-s | --ssh)
		MODE="ssh"
		if [[ $# -gt 1 && ! "$2" =~ ^- ]]; then
			SSH_TARGET="$2"
			shift 2
		else
			shift
		fi
		;;
	--http)
		SCHEME="http"
		shift
		;;
	--host)
		if [[ $# -lt 2 ]]; then
			echo "Error: --host requires a value." >&2
			exit 1
		fi
		HOST="$2"
		shift 2
		;;
	--port)
		if [[ $# -lt 2 ]]; then
			echo "Error: --port requires a value." >&2
			exit 1
		fi
		PORT="$2"
		shift 2
		;;
	--token)
		if [[ $# -lt 2 ]]; then
			echo "Error: --token requires a value." >&2
			exit 1
		fi
		TOKEN="$2"
		shift 2
		;;
	--tokens-file)
		if [[ $# -lt 2 ]]; then
			echo "Error: --tokens-file requires a value." >&2
			exit 1
		fi
		TOKENS_FILE="$2"
		shift 2
		;;
	*)
		echo "Unknown argument: $1" >&2
		usage >&2
		exit 1
		;;
	esac
done

print_instructions() {
	cat <<EOF
================================================================================
Event Horizon Tower Companion Update Guide
================================================================================
Target Host: zephyr-citadel ($HOST)

1. SSH into the tower:
   ssh zephyr-citadel   # or: ssh <user>@$HOST

2. Run the update command on the tower:
   $UPDATE_COMMAND

--------------------------------------------------------------------------------
Verification:
Once restarted, verify the companion /outputs API from this Mac:
   $0 --verify

Or run update remotely via SSH:
   $0 --ssh [user@]zephyr-citadel
================================================================================
EOF
}

extract_token() {
	if [[ -n "$TOKEN" ]]; then
		echo "$TOKEN"
		return 0
	fi

	if [[ ! -f "$TOKENS_FILE" ]]; then
		echo "Error: Token file not found at '$TOKENS_FILE'." >&2
		echo "Either pair Event Horizon with the host PC first or specify --token <TOKEN>." >&2
		return 1
	fi

	local extracted
	extracted=$(python3 - "$TOKENS_FILE" <<'PYEOF'
import json, sys

path = sys.argv[1]
try:
    with open(path, "r", encoding="utf-8") as f:
        data = json.load(f)
    hosts = data.get("hosts", {})
    for hid, info in hosts.items():
        if isinstance(info, dict) and info.get("token"):
            print(info["token"])
            sys.exit(0)
    sys.exit(1)
except Exception:
    sys.exit(1)
PYEOF
) || true

	if [[ -z "$extracted" ]]; then
		echo "Error: Could not extract a valid companion token from '$TOKENS_FILE'." >&2
		echo "Please verify that the host is paired or provide --token <TOKEN>." >&2
		return 1
	fi

	echo "$extracted"
}

verify_companion() {
	local auth_token
	if ! auth_token=$(extract_token); then
		exit 1
	fi

	local target_url="${SCHEME}://${HOST}:${PORT}/outputs"
	echo "Probing Companion API: $target_url ..."

	# Probe hello endpoint first to check basic connectivity and version
	local hello_url="${SCHEME}://${HOST}:${PORT}/hello"
	local hello_resp
	hello_resp=$(curl -k -s -m 4 "$hello_url" 2>/dev/null || true)
	if [[ -n "$hello_resp" ]]; then
		echo "Host reachable. Hello response: $hello_resp"
	fi

	# Query /outputs endpoint
	local raw_response
	raw_response=$(curl -k -s -w "\n%{http_code}" \
		--connect-timeout 5 \
		--max-time 10 \
		-H "Authorization: Bearer ${auth_token}" \
		-H "Accept: application/json" \
		"$target_url" 2>&1 || true)

	local http_status
	http_status=$(printf '%s\n' "$raw_response" | tail -n1)
	local http_body
	http_body=$(printf '%s\n' "$raw_response" | sed '$d')

	case "$http_status" in
	200)
		python3 - "$http_body" <<'PYEOF'
import json, sys

body = sys.argv[1]
try:
    data = json.loads(body)
except Exception as e:
    print(f"Error: Response is not valid JSON: {e}", file=sys.stderr)
    print(f"Raw body: {body}", file=sys.stderr)
    sys.exit(1)

if not isinstance(data, dict) or "outputs" not in data:
    print("Error: JSON response does not contain 'outputs' key.", file=sys.stderr)
    print(f"Payload: {data}", file=sys.stderr)
    sys.exit(2)

outputs = data.get("outputs", [])
if not isinstance(outputs, list):
    print("Error: 'outputs' field is not a list.", file=sys.stderr)
    sys.exit(3)

active_id = data.get("active_id", "")
connected = [o for o in outputs if o.get("connected", False)]

print(f"\nDiscovered {len(outputs)} output(s) ({len(connected)} connected):")
for o in outputs:
    name = o.get("name", "Unknown")
    oid = o.get("id", "")
    conn = o.get("connector", "")
    is_conn = o.get("connected", False)
    is_virt = o.get("is_virtual", False)
    status = "CONNECTED" if is_conn else "DISCONNECTED"
    active = " [ACTIVE]" if oid == active_id else ""
    kind = "Virtual" if is_virt else "Physical"
    cur = o.get("current_mode") or {}
    w = cur.get("width")
    h = cur.get("height")
    r = cur.get("refresh")
    mode_str = f" @ {w}x{h} {r}Hz" if (w and h and r) else ""
    print(f"  • {name} ({kind}) [{oid} / {conn}]: {status}{active}{mode_str}")

if not connected:
    print("\nWarning: No outputs are currently marked as connected.", file=sys.stderr)
    sys.exit(4)

physical = [o for o in connected if not o.get("is_virtual", False)]
if physical:
    names = ", ".join(o.get("name", "Display") for o in physical)
    print(f"\nPhysical connected display(s) verified: {names}")
else:
    print("\nNotice: Only virtual display is currently connected.")

sys.exit(0)
PYEOF
		local py_exit=$?
		if [[ $py_exit -eq 0 ]]; then
			echo ""
			echo "================================================================================"
			echo "✓ SUCCESS: Companion on $HOST:$PORT is running updated binary with /outputs API."
			echo "================================================================================"
			exit 0
		else
			echo ""
			echo "✗ Output validation failed (exit code $py_exit)." >&2
			exit "$py_exit"
		fi
		;;
	404)
		echo "" >&2
		echo "================================================================================" >&2
		echo "✗ FAILED: Received HTTP 404 Not Found from $target_url" >&2
		echo "================================================================================" >&2
		echo "Reason:" >&2
		echo "  The companion on '$HOST' is running an older binary that lacks the /outputs endpoint." >&2
		echo "" >&2
		echo "To update the tower companion, run this command on zephyr-citadel:" >&2
		echo "  $UPDATE_COMMAND" >&2
		echo "" >&2
		echo "Then rerun this verification:" >&2
		echo "  $0 --verify" >&2
		echo "================================================================================" >&2
		exit 2
		;;
	401 | 403)
		echo "" >&2
		echo "================================================================================" >&2
		echo "✗ FAILED: Received HTTP $http_status (Unauthorized) from $target_url" >&2
		echo "================================================================================" >&2
		echo "Reason:" >&2
		echo "  The companion rejected the Bearer token." >&2
		echo "  Tokens file: $TOKENS_FILE" >&2
		echo "  Pair the Mac app with the host again or specify --token <TOKEN>." >&2
		echo "================================================================================" >&2
		exit 3
		;;
	*)
		echo "" >&2
		echo "================================================================================" >&2
		echo "✗ FAILED: Could not reach $target_url (HTTP status: ${http_status:-none})" >&2
		echo "================================================================================" >&2
		echo "Raw error response:" >&2
		printf '%s\n' "$raw_response" >&2
		echo "" >&2
		echo "Troubleshooting:" >&2
		echo "  1. Check if the companion service is active on the tower:" >&2
		echo "     systemctl --user status event-horizon-companion.service" >&2
		echo "  2. Check firewall or port forwarding for port $PORT (TCP)." >&2
		echo "  3. Verify network reachability: ping -c 2 $HOST" >&2
		echo "================================================================================" >&2
		exit 1
		;;
	esac
}

run_ssh_update() {
	local target="${SSH_TARGET:-zephyr-citadel}"
	echo "Attempting remote update on '$target' via SSH..."
	ssh -t "$target" "$UPDATE_COMMAND"
	echo ""
	echo "Update command executed on '$target'. Verifying companion..."
	sleep 2
	verify_companion
}

case "$MODE" in
instructions)
	print_instructions
	;;
verify)
	verify_companion
	;;
ssh)
	run_ssh_update
	;;
esac
