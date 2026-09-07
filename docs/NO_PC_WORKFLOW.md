# Building a game with no development machine

`project.godot` points here, because almost every setting in it is a consequence
of this constraint rather than a preference.

---

## The constraint

**There is no PC.** No editor, no local run, no `adb logcat`, no profiler. The
loop is:

```
commit → CI → download → install → play
        ~6 minutes, every single time
```

Tuning how a joystick feels takes fifty small adjustments. At six minutes each
that is five hours, and the project dies somewhere in hour two.

Everything below exists to break that loop. These are not conveniences — they
are the load-bearing structure of the whole project, and the first three
milestones were spent building them rather than building the game.

---

## 1. Nothing that affects feel is a hardcoded constant

**49 tuning keys**, all in `data/tuning_defaults.json`, all adjustable on the
phone at runtime, all applying live with no restart.

```gdscript
var speed := Tuning.get_value("move_speed")     # never a `const`
```

Tap **DBG** (top-right) for a slider per parameter, grouped by
Movement / Bow / Quiver / Aim assist / Feel / Camera / Art / Regen / Targets.

**The workflow this creates:** tune on the phone in real time → **Copy JSON** →
paste into chat → the values are committed as the new defaults. That collapses a
six-minute round trip to seconds, and it is the only reason the control feel is
tunable at all ([ADR-0004](decisions/0004-runtime-tuning.md)).

`test_tuning_keys.gd` scans the source for every `Tuning.get_value("…")` and
asserts the key exists. A missing key returns `0.0` with only a pushed error —
on a phone that looks like "the game is broken" with no visible cause.

## 2. The game reports on itself

No PC means no `adb logcat`. So `debug/file_logging/enable_file_logging=true`,
and the debug overlay has:

- **Log tab** — tails `user://logs/godot.log` with a copy button. This is the
  only way to find out why something broke.
- **Info tab** — commit hash, device, renderer, resolution, safe area, FPS.

The commit hash matters more than it looks: with multiple channels and a
browser cache, "which build am I actually looking at" is a real question.

The overlay compiles out of release builds (`OS.is_debug_build()`).

## 3. Authoring must work without an editor

- **Arenas are ASCII text**, parsed at runtime — a layout change is typeable and
  reviewable in a diff on a phone ([ADR-0005](decisions/0005-text-first-authoring.md)).
- **Scenes are built in code.** There is exactly one `.tscn`, containing one
  node. Every hand-written scene file is a chance to break something invisible
  until CI runs.
- **Characters are hand-written SVG** — two layers, tinted per character.

## 4. Screenshots, because nobody can look at the game

`godot --headless` never calls `_draw()`. `tools/render_test.sh` runs a real
windowed Godot under Xvfb with software GL and writes a PNG; the combat mode
drives scripted input and captures on impact.

**This is the single most valuable tool in the repository.** Most bugs found in
this project were found by looking at a picture, not by a failing assertion.
See [CICD.md §3](CICD.md#why-the-render-test-is-worth-its-complexity).

## 5. CI has to mean more than "it compiled"

Eleven gates, each traceable to a specific failure. See
[CICD.md §3](CICD.md#3-the-gates-in-order).

The hardest-won of them: **verify the artifact, not the process.** A green run
says the pipeline worked. It says nothing about whether the thing a player
installs actually contains a map.

---

## What this costs

Worth stating, so the trade is visible rather than assumed:

- **Three milestones went into tooling before the game.** M0 was the pipeline,
  and the tuning panel was pulled forward into M1 out of necessity.
- **Some things simply cannot be verified here.** Frame rate, thermals and touch
  latency need the physical device. `dorbra.github.io` and `dl.google.com` are
  both blocked from the development container, so the web channel and the Android
  SDK are only reachable from CI or the phone.
- **Every gate is code that has to be maintained.** `verify_pack.sh`,
  `publish_web.sh`, `render_test.sh` and `smoke_test.sh` are ~400 lines of shell
  and GDScript that ship no gameplay.

The alternative was a six-minute feedback loop on a game whose entire quality
question is "does this feel right in the hand". That was not a workable project.
