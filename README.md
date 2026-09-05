# OogOog

A top-down archer brawler for Android. Short matches, twin-thumb controls,
travelling arrows, out-of-combat health regen.

Built with **Godot 4.7.1** (GDScript), **without a local development machine** —
every build is produced by GitHub Actions.

---

## Play it

| Channel | Link | Loop | Use for |
|---|---|---|---|
| **Web** | GitHub Pages (see the repo's Pages URL) | ~2–3 min, just refresh | Movement, aim, feel, balance |
| **APK** | [`dev` release](../../releases/tag/dev) | ~5–8 min, download + install | Real performance, thermals, true touch latency |

**Never judge performance in the browser** — the web build is single-threaded and
its timing does not match native. The APK is the source of truth.

**One-time phone setup:** Settings → Apps → Chrome → *Install unknown apps* → allow.
Android silently refuses the install otherwise.

---

## The no-PC workflow

The constraint that shapes this whole repo: a code change takes ~10 minutes to
reach the phone. Tuning how a joystick feels needs fifty small adjustments, and
at 10 minutes each that is unworkable. Three mechanisms exist to get around it.

### 1. Nothing that affects feel is a hardcoded constant

Every feel parameter lives in [`data/tuning_defaults.json`](data/tuning_defaults.json)
and is read through the `Tuning` autoload:

```gdscript
_speed = Tuning.get_value("move_speed")
Tuning.changed.connect(_on_tuning_changed)   # hot paths cache, they don't poll
```

### 2. Tune on the phone, in real time

Tap **DBG** (top-right) to open the debug overlay:

- **Tuning** — a slider per parameter, grouped. Changes apply live, no restart.
  **Copy JSON** puts the current values on the clipboard → paste them into chat →
  they get committed as the new defaults.
- **Log** — tails `user://logs/godot.log` with a copy button. This is the only way
  to see why something broke; there is no `adb logcat` without a PC.
- **Info** — commit hash, device model, renderer, resolution, safe area, FPS.

The overlay is compiled out of release builds (`OS.is_debug_build()`).

### 3. CI has to mean more than "it compiled"

Because nothing can be run locally by the person building this, every push runs:

1. **Version check** — `.godot-version` must match the workflow's pinned version.
2. **`gdformat --check` + `gdlint`**.
3. **`--import`** — builds the `.godot/` cache. Skipping this is the classic cause
   of a green build that produces a broken artifact.
4. **[Boot smoke test](tools/smoke_test.sh)** — actually launches the main scene
   headless for 300 frames and fails on any engine or script error. This is the
   crash-on-launch tripwire; without it that costs a full install round trip to find.
5. Only then: web export, Android export, publish.

---

## Layout

```
scenes/         main.tscn — kept minimal; scenes are built in code where practical
src/
  main.gd       M0 pipeline proof (bouncing box driven by Tuning)
  debug/        tuning.gd, debug_overlay.gd, build_info.gd
data/
  tuning_defaults.json   every feel parameter
  build_stamp.json       overwritten by CI so the app can identify its own commit
tools/
  smoke_test.sh
```

## Conventions

- **GDScript, not C#.** Godot's C# Android export is experimental (arm64/x64 only,
  deprecated `monovm` runtime, slow JIT startup). GDScript is the supported path.
- **One renderer everywhere** (`gl_compatibility`). Flat 2D gains nothing from
  Vulkan, and a single renderer removes a whole class of
  "works in the browser, breaks on the device" bugs.
- **arm64 only** — halves the APK; every relevant device is arm64.
- **Text-first authoring.** Arenas will be ASCII grids parsed at runtime rather
  than hand-authored `.tscn` tilemap data, because these have to be edited and
  reviewed without an editor.

## Local development (optional)

If you do have a machine:

```bash
godot --headless --path . --import
./tools/smoke_test.sh /path/to/godot 300
godot --headless --path . --export-debug "Web" build/web/index.html
```
