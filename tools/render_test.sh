#!/usr/bin/env bash
# Render test + screenshot.
#
# The headless smoke test never calls _draw(), so the entire rendering path was
# unverified: a typo in a draw call would sail through CI and only surface as a
# black screen on the phone, ten minutes later. This runs the real scene under a
# virtual display with software OpenGL, fails on any script error, and saves a
# PNG of the result that a human (or Claude) can actually look at.
#
# Usage: tools/render_test.sh <godot-binary> [frames] [output.png] [idle|combat]
set -uo pipefail

GODOT="${1:?usage: render_test.sh <godot-binary> [frames] [out.png]}"
FRAMES="${2:-90}"
OUT="${3:-build/shot.png}"
MODE="${4:-idle}"
LOG="$(mktemp)"

if ! command -v xvfb-run >/dev/null 2>&1; then
  echo "::error::xvfb-run not found — install xvfb to run the render test"
  exit 1
fi

mkdir -p "$(dirname "$OUT")"

# Import first, always. A render started while the .godot/ cache is still being
# built fails with resource errors that vanish on the next run — a spurious red
# that has now cost three debugging detours. Importing here makes the script
# deterministic regardless of what ran before it.
echo "==> ensuring import cache is current"
"$GODOT" --headless --path . --import >/dev/null 2>&1 || true

echo "==> rendering ${FRAMES} frames offscreen (mode: ${MODE})"
LIBGL_ALWAYS_SOFTWARE=1 xvfb-run -a "$GODOT" \
  --path . --rendering-driver opengl3 \
  --script tools/screenshot.gd -- "$FRAMES" "$OUT" "$MODE" >"$LOG" 2>&1
STATUS=$?

# This container has no sound hardware. ALSA/PulseAudio failures are expected
# and unrelated to rendering, so they must not be read as real errors.
#
# "Failed to load cached shader, recompiling" is filtered for a subtler reason:
# it is a WARNING about a cold shader cache, and the error check below looks for
# "Failed to load" — so on any runner whose cache is empty this gate went red
# with nothing wrong. Found by hitting it on a fresh container. Filtered by its
# own exact wording rather than by loosening "Failed to load", which is what
# catches a real script that will not load.
grep -viE "alsa|pulse|snd_|v-sync|audio driver|audio_server|audio_driver|cached shader" "$LOG"

if [ "$STATUS" -ne 0 ]; then
  echo "::error::Render test exited with status ${STATUS}"
  exit 1
fi

if grep -viE "alsa|pulse|snd_|v-sync|audio driver|audio_server|audio_driver|cached shader" "$LOG" \
   | grep -qE "SCRIPT ERROR|USER ERROR|Parse Error|Failed to load"; then
  echo "::error::Script errors during rendering (see log above)"
  exit 1
fi

if [ ! -s "$OUT" ]; then
  echo "::error::No screenshot produced at ${OUT}"
  exit 1
fi

echo "==> render test passed, screenshot at ${OUT}"
