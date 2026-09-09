# ADR-0021: A saved tuning value must never override the build invisibly

**Status:** Accepted · M3.3

## Context

> *"the gameplay is still bad and feels weird — characters move around too fast"*

Movement speed had been cut from 250 to 150 px/s two releases earlier, and the
report described the old behaviour. Asked directly, the user was **not sure**
whether they had ever pressed **Save** in the on-device tuning panel.

That question decides whether the last two releases reached the device at all,
and until now nothing in the game could answer it.

`src/debug/tuning.gd` loads `res://data/tuning_defaults.json`, then applies
`user://tuning.json` over the top **key by key**:

```gdscript
for key: String in parsed:
    if _defs.has(key):
        _values[key] = float(parsed[key])
```

`user://` is the application's own data directory. **It survives an APK
update.** So one press of Save pins those keys on that device permanently: every
later release ships a new default for them and every later release is ignored,
for as long as the file exists.

None of this was visible. No badge, no log line, nothing on the sliders. The
pipeline was green, the APK installed, the commit hash in the HUD was correct —
and the numbers the game ran were from whenever Save had last been pressed.

## Decision

**The override still wins. It just cannot happen silently any more.**

Keeping the override is deliberate. Discarding somebody's saved tuning because a
shipped default moved would trade one silent surprise for another, and on a
project whose entire workflow is "tune on the phone, paste the JSON back", the
saved file is the user's work.

So `Tuning` records which keys came from the user file and reports them:

- `Tuning.overridden_keys()` names them.
- The debug panel shows a badge above the buttons — *"N value(s) SAVED ON THIS
  DEVICE, overriding the build: … Tap Reset to run what was shipped"* — beside
  the Reset that already deletes the file.
- One line goes to `print()` at boot, so it lands in the **Log tab**, which is
  the only place the user can read anything without a PC.
- **`save()` marks the keys immediately.** The badge appears at the moment the
  override is created, rather than two releases later when it starts doing
  damage. Learning the mechanism while pressing the button is the point.

## Consequences

**Good:**
- "Is my phone running what you shipped?" is answerable in one glance, forever.
- The failure is self-describing: the badge names the exact keys, so a stale
  `move_speed` cannot masquerade as a bad tuning decision again.

**Bad:**
- A user who deliberately tunes and saves now sees a permanent warning. That is
  the correct trade — the warning is *true* — but it is noise for someone who
  knows what they did.
- `save()` marks every key rather than only the changed ones, because the file
  is written whole. The badge therefore says "66 values" after any Save, which
  overstates how much was deliberately changed.

## Verification

`tests/test_tuning_overrides.gd` — a saved value is both applied *and* reported;
`reset()` clears the file, the values and the report together; a build with no
saved file reports nothing (so the badge cannot cry wolf); an unknown key from an
older build is neither injected nor reported.

`tools/verify_ui.gd` — the badge is **hidden on a clean build, visible after a
Save, names the key, and disappears on Reset**, checked by driving the real
overlay in the real scene. Asserting `overridden_keys()` alone would prove the
data is right and prove nothing about whether anybody can see it, which is
exactly the gap [ADR-0019](0019-appearance-is-not-behaviour.md) was written
about. Five of the seventeen interaction checks are this badge.

## The general lesson

[ADR-0012](0012-verify-inside-the-artifact.md) says verify the artifact rather
than the process, and [ADR-0019](0019-appearance-is-not-behaviour.md) sharpens it
to verifying the artifact doing its job. This is the third turn of the same
screw:

**A value that silently wins over the shipped one makes the whole pipeline a
liar.** Every gate in this repository verifies what is *in the build*. None of
them could see what the device was actually running.
