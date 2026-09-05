#!/usr/bin/env bash
# Boot smoke test.
#
# CI is the only place this project can be run, and "it compiled" is not the
# same as "it launches". This boots the real main scene headless — autoloads,
# scene tree, physics, the lot — runs it for a while, and fails on any engine
# or script error. It is the tripwire for crash-on-launch, which would
# otherwise cost a full download-and-install round trip to discover.
#
# Usage: tools/smoke_test.sh <path-to-godot-binary> [frames]
set -uo pipefail

GODOT="${1:?usage: smoke_test.sh <godot-binary> [frames]}"
FRAMES="${2:-300}"
LOG="$(mktemp)"

echo "==> booting main scene headless for ${FRAMES} frames"
"$GODOT" --headless --path . --quit-after "$FRAMES" >"$LOG" 2>&1
STATUS=$?

cat "$LOG"

if [ "$STATUS" -ne 0 ]; then
  echo "::error::Godot exited with status ${STATUS}"
  exit 1
fi

# Godot reports script and engine errors on stdout/stderr while still exiting 0,
# so the exit code alone is not enough — scan the output too.
if grep -qE "SCRIPT ERROR|ERROR:|USER ERROR|Parse Error|Failed to load" "$LOG"; then
  echo "::error::Errors detected during headless boot (see log above)"
  exit 1
fi

echo "==> smoke test passed"
