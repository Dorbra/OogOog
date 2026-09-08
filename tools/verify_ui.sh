#!/usr/bin/env bash
# Interaction test: can the on-screen controls actually be touched?
#
# A build shipped where the setup screen could not be dismissed at all — tapping
# did nothing and the game was stuck on its first screen. Every gate was green.
# The unit tests build no scene tree; the render captures drew the screen
# perfectly, because _draw() is not clipped by a Control's rect. So the pictures
# looked right while the thing was completely dead.
#
# A capture proves it drew. Only delivering an input proves it works.
#
# Needs a real display for the same reason the render test does: headless gives a
# square viewport and does not route GUI input, so a tap there would prove
# nothing while appearing to pass.
#
# Usage: tools/verify_ui.sh <path-to-godot-binary>
set -uo pipefail

GODOT="${1:?usage: verify_ui.sh <godot-binary>}"
LOG="$(mktemp)"

if ! command -v xvfb-run >/dev/null 2>&1; then
  echo "::error::xvfb-run not found — install xvfb to run the UI test"
  exit 1
fi

# Import first, for the same reason render_test.sh does: a run started while the
# .godot/ cache is still building fails with resource errors that vanish on the
# next run.
echo "==> ensuring import cache is current"
"$GODOT" --headless --path . --import >/dev/null 2>&1 || true

echo "==> delivering taps to the real main scene"
LIBGL_ALWAYS_SOFTWARE=1 xvfb-run -a "$GODOT" \
  --path . --rendering-driver opengl3 \
  --script tools/verify_ui.gd >"$LOG" 2>&1
STATUS=$?

NOISE="alsa|pulse|snd_|v-sync|audio driver|audio_server|audio_driver|cached shader"
grep -viE "$NOISE" "$LOG"

if [ "$STATUS" -ne 0 ]; then
  echo "::error::UI interaction test failed — a control cannot be touched"
  exit 1
fi

if grep -viE "$NOISE" "$LOG" | grep -qE "SCRIPT ERROR|USER ERROR|Parse Error|Failed to load script"; then
  echo "::error::Script errors during the UI test (see log above)"
  exit 1
fi

echo "==> UI interaction test passed"
