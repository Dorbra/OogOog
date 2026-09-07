#!/usr/bin/env bash
# Connects two headless Godot processes over 127.0.0.1 and asserts that state
# actually crosses between them.
#
# The whole networking path is exercised here except the physical radio: server
# creation, client connection, peer signals, RPC delivery, and positions moving
# from one process into the other. That is the part which breaks from a renamed
# API or a wrong @rpc annotation, and it is the part that would otherwise only
# be discovered by installing on two phones.
#
# What this canNOT tell you: whether the household router carries the traffic,
# and what the real over-the-air latency is. Those need hardware, and answering
# them is the entire point of the M3.0 spike.
#
# Usage: test_net_loopback.sh <godot-binary>

set -uo pipefail

GODOT="${1:?usage: test_net_loopback.sh <godot-binary>}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

HOST_PID=""
OUT="$(mktemp -d)"
# Kill AND REAP, rather than a bare kill. `kill` returns before the process has
# actually gone, and a Godot still shutting down holds the .godot/ import cache;
# the next Godot invocation in the same CI job would then race it. This is
# defensive — no such failure has been attributed to it — but a background
# process outliving the script that started it is worth closing off regardless.
cleanup() {
	if [ -n "${HOST_PID:-}" ] && kill -0 "$HOST_PID" 2>/dev/null; then
		kill "$HOST_PID" 2>/dev/null || true
		wait "$HOST_PID" 2>/dev/null || true
	fi
	rm -rf "$OUT"
}
trap cleanup EXIT

echo "== starting host"
"$GODOT" --headless --path . --script tools/net_probe.gd -- host > "${OUT}/host.log" 2>&1 &
HOST_PID=$!

# The server has to be listening before the client dials, and there is no signal
# to wait on from out here. A short fixed wait is the honest approach; the probe
# itself has a 15s timeout, so a slow start shows up as a real failure rather
# than a race.
sleep 3

if ! kill -0 "$HOST_PID" 2>/dev/null; then
	echo "::error::host exited before the client started"
	cat "${OUT}/host.log"
	exit 1
fi

echo "== starting client"
"$GODOT" --headless --path . --script tools/net_probe.gd -- join 127.0.0.1 > "${OUT}/client.log" 2>&1
CLIENT_RC=$?

wait "$HOST_PID"
HOST_RC=$?

echo
echo "── host ──"
cat "${OUT}/host.log"
echo "── client ──"
cat "${OUT}/client.log"
echo

if [ "$HOST_RC" -ne 0 ] || [ "$CLIENT_RC" -ne 0 ]; then
	echo "::error::loopback failed (host rc=${HOST_RC}, client rc=${CLIENT_RC})"
	exit 1
fi

# A green exit code is not enough on its own: the probe must have said why.
if ! grep -q "received position from" "${OUT}/host.log"; then
	echo "::error::host never received a position from the client"
	exit 1
fi
if ! grep -q "received position from" "${OUT}/client.log"; then
	echo "::error::client never received a position from the host"
	exit 1
fi

echo "PASS — two processes connected and exchanged state both ways"
