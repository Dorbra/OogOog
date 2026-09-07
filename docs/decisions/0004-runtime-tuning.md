# ADR-0004: No feel constant is a literal

**Status:** Accepted · M1

## Context

The quality question for this game is "does it feel right in the hand". That is
not answerable by reasoning — only by holding the phone. And the loop from a
changed number to a phone is **~6 minutes**.

Tuning a joystick takes fifty adjustments. At six minutes each, M1 becomes
unbearable and the project dies there.

## Decision

**Every parameter that affects feel lives in `data/tuning_defaults.json` and is
adjustable on the device at runtime.** No `const`, no magic number, no
"temporarily hardcode it and fix later".

- `Tuning` autoload loads defaults, overridden by `user://tuning.json`.
- Each entry carries `{value, min, max, group}` so the panel builds itself.
- The debug overlay renders a slider per key, grouped. Changes apply **live**.
- **Copy JSON** puts the current values on the clipboard → pasted into chat →
  committed as the new defaults.

Currently **49 keys** across 10 groups.

## Consequences

**Good:**
- **The tuning loop drops from six minutes to seconds.** This is the single
  highest-leverage decision in the project.
- Balance arguments are settled with thumbs rather than in a PR thread. Every
  "should this be 0.3 or 0.5" question has an answer nobody has to guess.
- It changes how disagreements get resolved: when firing model was contested,
  the answer was to **ship both behind a toggle** and let the phone decide.

**Bad:**
- **A dictionary lookup in hot paths.** `Tuning.get_value()` is called ~40 times
  across the codebase, several per tick. The design anticipated this — hot paths
  are meant to cache on the `changed` signal — but that has not been done yet.
  It is on the tech-debt list and is a real cost, not a theoretical one.
- **A missing key returns `0.0` and only pushes an error**, which on a phone
  looks like "the game is broken" with no visible cause. `test_tuning_keys.gd`
  exists specifically for this: it scans source for every `get_value("…")` and
  asserts the key exists.
- **Autoloads do not run `_ready()` under `--script`.** The headless test runner
  registers the autoload but never adds it to the tree, so every lookup returned
  `0.0` silently. Fixed with lazy `_ensure_loaded()` in every public accessor —
  worth knowing before writing another autoload.

## Alternatives

| | Verdict |
|---|---|
| Exported `@export` vars on nodes | Rejected — requires an editor, which does not exist here |
| A config file edited and redeployed | Rejected — that *is* the six-minute loop |
| Hot-reload of GDScript | Rejected — does not work on a deployed Android build |
