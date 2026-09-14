# OogOog

A **3v3 top-down cat shooter for Android, played over local WiFi**. Short
matches, twin-thumb controls, three classes, travelling bullets, out-of-combat
health regen.

Three people in one room, each on their own phone — that is what it is for, and
everything else follows from it.

Built with **Godot 4.7.1** (GDScript), **without a local development machine** —
every build is produced by GitHub Actions.

---

## Play it

| Channel | Link | Loop | Use for |
|---|---|---|---|
| **Web** | GitHub Pages — `main` at the site root, each PR at `/pr/<n>/` | ~2–3 min, just refresh | Movement, aim, feel, balance |
| **APK** | [`dev` release](../../releases/tag/dev) | ~5–8 min, download + install | Real performance, thermals, true touch latency |

**Never judge performance in the browser** — the web build is single-threaded and
its timing does not match native. The APK is the source of truth.

### One-time setup

1. **Point GitHub Pages at the `gh-pages` branch**
   (Settings → Pages → Source: **Deploy from a branch** → `gh-pages` / `(root)`).
   The branch is created by the first build that runs after this change, so if
   the branch is not offered yet, let a build finish and come back.

   Then **Settings → Environments → `github-pages` → Deployment branches and
   tags → No restriction.** This one is not optional and not obvious: GitHub
   runs its own `pages-build-deployment` workflow for branch-served Pages, and
   that workflow goes through this environment. A stale branch rule here refuses
   it silently — see [CONTRIBUTING.md](CONTRIBUTING.md#why-the-web-build-is-published-by-pushing-a-branch),
   which is worth reading once, because the failure produces no logs at all.
2. **Allow APK installs on the phone**: Settings → Apps → Chrome →
   *Install unknown apps* → allow. Android silently refuses the install otherwise.
3. **Protect `main`** (Settings → Branches → add a rule for `main`):
   - **Require a pull request before merging**, and leave **Require approvals
     unchecked**. There is no "0" to select — the count starts at 1 — and on a
     solo repo any approval requirement deadlocks, because GitHub forbids
     approving your own pull request.
   - **Require status checks to pass** → **`build`**. Pick that specific check
     rather than the whole workflow, so adding a job later cannot silently
     change what gates a merge.
   - Require branches to be up to date before merging.
   - Block force pushes.

## How work lands

`main` is protected and always releasable. Everything goes through a branch and
a pull request — see [CONTRIBUTING.md](CONTRIBUTING.md) for the full workflow.

```
feat/my-thing  ──PR──▶  main
     │                    │
  pr-<n> release      dev release
  (play it before     (the link you
   it merges)          bookmark)
```

Opening a PR builds it and comments the APK link on the thread, so a change can
be played on the phone **before** it is approved. That matters here more than in
most projects: whether something feels right is not reviewable in a diff.

Each PR also gets its own web preview at `/pr/<n>/`, removed when the PR closes.
It is a separate directory from the site root, so a PR can never overwrite the
URL you bookmark and two open PRs cannot overwrite each other.

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
- **Info** — commit hash, device model, renderer, resolution, safe area, FPS,
  and the worst frame seen since boot.
- **Net** — role, peers, **worst ping**, last error, and a manual-address box for
  when broadcast discovery is blocked by the router. The ping is the number the
  netcode design rests on, so it prints its own verdict against 50 ms.

The overlay is present whenever `OS.is_debug_build()` **or** the `dbg` feature
tag is set, so it survives a release web export — losing the tuning panel from
the fast channel would cost more than the five megabytes it saves.

### 3. CI has to mean more than "it compiled"

Because nothing can be run locally by the person building this, every push runs:

1. **Version check** — `.godot-version` must match the workflow's pinned version.
2. **`gdformat --check` + `gdlint`**.
3. **`--import`** — builds the `.godot/` cache. Skipping this is the classic cause
   of a green build that produces a broken artifact.
4. **[Boot smoke test](tools/smoke_test.sh)** — actually launches the main scene
   headless for 300 frames and fails on any engine or script error. This is the
   crash-on-launch tripwire; without it that costs a full install round trip to find.
5. **Unit tests**, **six render captures**, **pack verification**, a
   **two-process LAN loopback**, and a **UI interaction test** that delivers real
   taps — because a capture proves the screen drew, not that anybody can touch it.
6. Only then: web export, Android export, publish.

Thirteen gates in all, each of which exists because something reached a device
broken. [docs/CICD.md](docs/CICD.md) has the list and the incident behind each.

---

## Layout

```
scenes/main.tscn      One node; everything else is built in code
src/
  main.gd             Thin orchestrator — builds the world, pumps input
  sim/                Simulation. Never reads Input, never touches a sprite.
                      input_command, sim_world, fighter, fighter_class, gun,
                      bullet, hazard, health, aim, match_state, snapshot
  ai/                 Producers of an InputCommand that are not thumbs:
                      bot_controller, grid_path, remote_controller
  net/                net_link (host/join/ping), lan_beacon (discovery),
                      net_game (roster, seats, snapshots) — autoloaded as `Lan`
  arena/              arena.gd — ASCII grid: walls, bushes, spawns, collision
  input/              touch_controls — multi-touch routed by FINGER INDEX
  view/               game_view, camera_rig, fx, hud, match_hud, match_screens,
                      lobby_screen, cat_view, terrain, palette, safe_area
  debug/              tuning, debug_overlay, build_info, frame_stats
assets/cats/          Hand-written SVG: tintable body + untinted face
data/
  arenas/arena_01.txt     the map, as text — edit it to change the level
  arenas/legend.json      symbol meanings and cell size
  classes.json            the three classes, as multipliers over the keys below
  tuning_defaults.json    every feel parameter, live-adjustable on device
  build_stamp.json        overwritten by CI so the app identifies its own commit
tests/                Run headless via tools/run_tests.gd
tools/                smoke_test.sh, render_test.sh, screenshot.gd, run_tests.gd,
                      verify_ui.sh, verify_pack.sh, measure_matches.gd,
                      measure_frame.gd, net_probe.gd,
                      publish_web.sh — pushes the web build to `gh-pages`
```

### Architecture

**The simulation never reads `Input` and never touches a sprite.** `sim/` runs
in `_physics_process` at a fixed 60 Hz; `view/` interpolates it for display and
subscribes to typed events (`hit`, `killed`, `fired`) rather than polling state.

That split is why the combat logic is unit-testable headlessly, and it is what
made same-WiFi multiplayer possible **without a rewrite**: the network became a
fourth producer of `InputCommand` alongside thumbs, bot AI and nobody-at-all, and
`SimWorld.tick()` did not change by a single line
([ADR-0032](docs/decisions/0032-the-network-is-a-command-producer.md)).

## Conventions

- **GDScript, not C#.** Godot's C# Android export is experimental (arm64/x64 only,
  deprecated `monovm` runtime, slow JIT startup). GDScript is the supported path.
- **One renderer everywhere** (`gl_compatibility`). Flat 2D gains nothing from
  Vulkan, and a single renderer removes a whole class of
  "works in the browser, breaks on the device" bugs.
- **arm64 only** — halves the APK; every relevant device is arm64.
- **Text-first authoring.** Arenas are ASCII grids parsed at runtime rather than
  hand-authored `.tscn` tilemap data, because they have to be edited and reviewed
  without an editor.
- **Pool anything spawned in combat** — bullets, hazards, particles, damage numbers.
  GDScript allocation churn shows up as frame hitches.

## Documentation

Full engineering documentation lives in **[docs/](docs/)**:

| | |
|---|---|
| [Architecture](docs/ARCHITECTURE.md) | Layers, module map, the frame, invariants |
| [Game design](docs/GAME_DESIGN.md) | Pillars, mechanics, roadmap, what was refused |
| [CI/CD](docs/CICD.md) | Pipeline, the thirteen gates, publishing, incident log |
| [No-PC workflow](docs/NO_PC_WORKFLOW.md) | The constraint that shapes everything else |
| [Decisions (ADRs)](docs/decisions/) | One file per decision: why, what it cost, what was rejected |

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for branch naming, the local gate to run
before pushing, and how PR builds reach your phone.
