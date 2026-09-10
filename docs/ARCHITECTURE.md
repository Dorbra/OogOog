# Architecture

How OogOog is put together, and why it is put together that way.

> Decisions referenced as `ADR-000n` are recorded in full under
> [`docs/decisions/`](decisions/). This document describes the *system*; the ADRs
> record *why each choice was made and what it cost*.

---

## 1. The one rule

**The simulation never reads input and never touches a sprite.**

Everything else follows from that sentence. It is not a style preference — it is
load-bearing for a project where nobody can run the game locally
([ADR-0003](decisions/0003-sim-view-split.md)).

```
┌─────────────┐   InputCommand   ┌─────────────┐   typed events   ┌─────────────┐
│  PRODUCERS  │ ───────────────▶ │     SIM     │ ───────────────▶ │    VIEW     │
│             │                  │             │                  │             │
│ thumbs      │                  │ pure logic  │   read-only      │ nodes       │
│ bot AI      │                  │ fixed 60 Hz │ ◀ ─ ─ ─ ─ ─ ─ ─  │ sprites     │
│ network (?) │                  │ no nodes    │   state for      │ camera, FX  │
└─────────────┘                  └─────────────┘   interpolation  └─────────────┘
```

Three consequences worth stating plainly:

- **The sim is unit-testable headless.** 370 assertions run in a few seconds
  with no display. That is the only correctness signal available to a project
  with no local machine.
- **Bots are not a special case.** A bot is a third thing that produces an
  `InputCommand`. It gets no privileged access to state and cannot cheat by
  construction. This stopped being an aspiration in M3.1d: `BotController`
  landed without a single change to `Fighter`, `SimWorld.tick()` or the view
  ([ADR-0014](decisions/0014-a-star-not-navigation-agent.md)).
- **LAN multiplayer stays possible without a rewrite.** The network would become
  another `InputCommand` producer. This is *not* a promise that it will be built.

---

## 2. Directory map

| Path | Layer | May depend on | Contains |
|---|---|---|---|
| `src/sim/` | Simulation | `Tuning`, `Arena` | `input_command`, `sim_world`, `fighter`, `bow`, `arrow`, `health` |
| `src/arena/` | World data | `Tuning` | `arena.gd` — ASCII grid, collision, spawns |
| `src/input/` | Producer | `Tuning`, Godot `Input` | `touch_controls.gd` |
| `src/sim/` also holds `match_state.gd` | Simulation | `Tuning` | Phases, score, clock and the win condition — see [ADR-0017](decisions/0017-the-match-is-sim-state.md) |
| `src/sim/` also holds `aim.gd` | Simulation | none | The one projectile-intercept solver, shared by the player's auto-aim and the bots — see [ADR-0020](decisions/0020-aim-assist-must-predict.md) |
| `src/ai/` | Producer | `src/sim/`, `src/arena/`, `Tuning` | `bot_controller.gd` — FSM and difficulty; `grid_path.gd` — A* over the arena grid |
| `src/sim/fighter_class.gd` | Simulation | `Tuning`, `data/classes.json` | What makes one cat shoot differently: multipliers over the global keys, never absolutes (ADR-0028) |
| `src/sim/hazard.gd` | Simulation | none | Pooled ground hazard — caltrops. Damage per second, never once on entry |
| `src/view/` | Presentation | everything | `game_view`, `camera_rig`, `fx`, `hud`, `cat_view`, `terrain`, `palette`, `safe_area` |
| `src/debug/` | Tooling | everything | `tuning`, `debug_overlay`, `build_info` |
| `src/main.gd` | Composition root | everything | wires the graph, pumps the tick |

**The dependency rule:** `sim/` must never import from `view/` or `input/`. If
you find yourself wanting to, the thing you actually want is an event
([ADR-0007](decisions/0007-typed-sim-events.md)).

`Arena` is the one shared type — it lives outside `sim/` because the view also
needs it to draw walls, but it is pure data and pure maths with no node in sight.

---

## 3. Scene graph

There is essentially **one** `.tscn` in the project:

```tscn
[node name="Main" type="Node2D"]
script = "res://src/main.gd"
```

Everything else is constructed in code, deliberately
([ADR-0005](decisions/0005-text-first-authoring.md)). What `main.gd` builds:

```
Main (Node2D)                       ← src/main.gd, composition root
├── TouchControls (Node)            ← reads touch, emits shot_released
├── CameraRig (Camera2D)            ← follow + clamp + trauma shake
├── GameView (Node2D)               ← world rendering, z_index 0
│   ├── canopy (Node2D)             ← z_index 3, bushes ABOVE cats
│   ├── CatView × N enemies         ← z_index 1
│   └── CatView player              ← z_index 2
├── Fx (Node2D)                     ← pooled particles/numbers/rings, hitstop
└── CanvasLayer (layer 1)           ← SCREEN space, not world space
    ├── overlay (Node2D)            ← floating joystick
    └── Hud (Node2D)                ← build stamp (magazine pips are in GameView)
```

Plus two autoloads declared in `project.godot`:

| Autoload | Why it is global |
|---|---|
| `Tuning` | Read from ~40 call sites across every layer; threading it through constructors would be noise ([ADR-0004](decisions/0004-runtime-tuning.md)) |
| `DebugOverlay` | Must be reachable from any scene and compiles out of release builds |

**Why the `CanvasLayer` matters:** the world is drawn through the camera, which
applies zoom and shake. The joystick follows the player's *thumb*, and the HUD
must sit at fixed screen corners. Drawing them in world space would make the
joystick drift and shake. `CanvasLayer` opts them out of the camera transform.

---

## 4. The frame

Two clocks, on purpose.

```
_physics_process(delta)   fixed 60 Hz          _process(delta)     display rate
─────────────────────────────────────          ─────────────────────────────────
 tick += 1                                      camera.follow()
 cmd ← TouchControls state                      hud ← bow state
 world.tick(cmd, delta)                         overlay.queue_redraw()
   ├ player.tick()  move, collide               GameView._draw()
   ├ dummies.tick() regen, knockback              alpha = physics_interpolation_fraction()
   ├ _try_fire()    if cmd.fire                   terrain → cats → arrows → bars
   └ _tick_arrows() walls, then targets          Fx._process()  pools advance
        └ emits hit / killed / arrow_expired
```

**Why fixed-step simulation:** gameplay that depends on frame rate is gameplay
that changes when the phone gets hot. A 120 Hz panel and a thermally-throttled
40 fps must produce the same fight.

**Why interpolation:** the sim advances in 16.7 ms jumps. Rendering raw sim
positions gives visible stepping on a 120 Hz screen. Every renderable carries
`prev_position`, and the view lerps by
`Engine.get_physics_interpolation_fraction()`.

### Ordering inside a tick is a correctness property

`SimWorld._tick_arrows()` resolves **walls before targets**, and shortens the
arrow's segment to the impact point first:

```gdscript
var wall := arena.cast_segment(from, arrow.position)
if wall["hit"]:
    arrow.position = wall["point"]     # segment truncated BEFORE target tests
for f in fighters: ...                  # so cover actually works
```

Reverse the order and a target standing behind a wall gets hit through it.

---

## 5. The simulation

### `SimWorld` — owns everything, ticks in a fixed order

```gdscript
signal hit(position, direction, damage, full_draw)
signal killed(position, direction)
signal fired(position, direction, draw_strength)
signal arrow_expired(position)
```

**Every point of damage in the game goes through `SimWorld.apply_damage()`.**
That single funnel is what guarantees the view cannot miss a hit — there is no
second path that damages something quietly ([ADR-0007](decisions/0007-typed-sim-events.md)).

### Component responsibilities

| Type | Owns | Notably does *not* own |
|---|---|---|
| `Fighter` | position, velocity, facing, `team`, `Health`, `Gun`, knockback, respawn | who is driving it |
| `Health` | hp, regen, death latch | anything visual |
| `Gun` | magazine, reload accumulator, fire-rate cooldown | the bullet |
| `Bullet` | position, velocity, damage, lifetime, `owner_team` | what it hits |
| `Arena` | grid, bounds, spawns, collision queries | anything that moves |

### Collision is pure maths, not a physics engine

No `Area2D`, no `PhysicsBody2D`, no collision layers
([ADR-0008](decisions/0008-no-physics-engine.md)). Three algorithms:

- **Bullet vs. target — swept circle.** At 1400 px/s a bullet covers ~23 px per
  tick against a 42 px target radius. Testing only the endpoint would let fast
  shots tunnel through. `Bullet.hits_circle()` tests the *segment travelled*.
- **Bullet vs. wall — DDA grid traversal** (Amanatides & Woo). Exact, ~25 lines,
  and unit-testable. Sampling points along the segment would reintroduce
  tunnelling in a second place, which is not a trade worth making for fewer
  lines.
- **Fighter vs. wall — circle push-out, iterated twice.** One pass leaves a circle
  wedged in a concave corner still overlapping the other wall. Velocity into the
  surface is cancelled on contact, otherwise the actor keeps accelerating into
  the wall and shoots off at full speed on release.

One subtlety the tests caught: escaping a wall by the *nearest* face ejects out
of a border cell into off-grid space, which is itself treated as solid — landing
somewhere worse than it started. `resolve_circle()` prefers the nearest face
whose neighbour is actually open, falling back to nearest only when a cell is
fully enclosed.

---

## 6. The arena is a text file

`data/arenas/arena_01.txt` — 24 × 14 cells at 60 px = a **1440 × 840** world.

Sized for 3v3 and **mirrored left/right**, so neither team gets better cover —
symmetry here is a fairness property, not a style choice. At the current zoom
roughly half the map is on screen at once, which is what keeps a three-minute
match about fighting rather than walking.

```
#  wall    blocks movement AND arrows
b  bush    blocks sight, NOT movement
P  spawn   9 of them; player takes the one nearest centre
.  open
```

**The file is the source of truth for world size.** Bounds come from
`cols × cell_size`, so editing the map resizes `SimWorld`, `Terrain` and
`CameraRig` at once. This replaced a `WORLD_SIZE` constant that three systems
had to agree on by hand.

Ragged rows and unknown characters are treated as open ground rather than
errors. The file is hand-edited on a phone; failing a build over a short line
would make the format hostile to the only person using it.

> **Trap, learned the hard way:** `.txt` is not a Godot *resource*, so
> `export_filter="all_resources"` silently dropped this file from every export
> for two merged PRs. See [ADR-0012](decisions/0012-verify-inside-the-artifact.md).

---

## 7. The view

### Rendering strategy: immediate mode, batched, culled

Terrain is drawn in `_draw()` rather than as hundreds of nodes.

| Layer | Draw calls | Technique |
|---|---|---|
| Ground | **1** | One tiled `NoiseTexture2D` across the whole world |
| Scatter (620 tufts, 90 flowers, 70 pebbles) | ~3 | `draw_multiline_colors` batching, culled to camera rect |
| Walls | 2 per visible cell | Culled via `Arena.cells_in_rect(view)` |
| Canopy (bushes) | 3 per visible cell | Separate node at `z_index = 3` |

Placement is **seeded** (`SEED = 20260906`), so the garden is identical across
runs. That matters more than it sounds: the screenshot test is the main art
feedback loop and is useless if the scenery reshuffles between renders.

**Bushes draw above the cats** because concealment only reads if the cat is
visually *inside* cover. Underneath the sprites it would look like a cat standing
on a green patch. The player fades to `modulate.a = 0.55` while concealed.

### Feedback is event-driven, and pooled

`Fx` subscribes to the sim's signals and owns fixed-size pools allocated once at
startup — 220 particles, 40 damage numbers, 24 rings
([ADR-0009](decisions/0009-pool-combat-objects.md)). Exhausting a pool drops the
effect; it never allocates mid-combat.

- **Hitstop** dips `Engine.time_scale`, so the sim, the view and the FX all
  freeze together and stay in sync. Anything that must keep moving during a
  freeze (the camera) uses unscaled delta explicitly.
- **Screenshake is trauma-based**, and shake is `trauma²`. Small hits barely
  register, a kill is unmistakable, and repeated hits *accumulate* rather than
  restarting a fixed animation.

---

## 8. Input

`TouchControls` is the one place that reads Godot's `Input`.

**The rule that prevents the classic bug:** a finger is assigned to a side
**once**, when it first touches down, and keeps that assignment until it lifts —
regardless of where it subsequently drags. Routing by *current position* is why
mobile twin-stick controls "randomly" break when a thumb crosses the midpoint
mid-drag.

```
Left half  → floating joystick. Appears where the thumb lands.
Right half → drag = direction, hold = power, release = loose.
```

Direction and power are independent axes of one gesture, which is why the archer
theme suits touch better than guns: the gesture and the fiction are the same
action ([GAME_DESIGN.md §3](GAME_DESIGN.md#3-the-bow-is-the-whole-control-scheme)).

Two non-obvious details:

- `Input.set_use_accumulated_input(false)` — without it, drag events are
  coalesced per frame and the draw gesture feels laggy in exactly the way that is
  hardest to diagnose on a phone.
- `aim_min_drag` (40 px): below the threshold the aim *holds its previous
  direction* instead of recomputing from a noisy short vector. A 10 px drag
  otherwise carries the same authority as a 200 px one once normalised, which is
  what made small movements swing shots across the arena.

---

## 9. Known debt, stated honestly

| Debt | Cost today | Where it gets paid |
|---|---|---|
| The smoke test boots into the setup screen, where nothing simulates | It covers less than it did; live-sim coverage moved to the render captures, which force `Phase.LIVE` | Unclaimed — worth a flag that starts a match, if the boot test is ever asked to do more than catch a crash |
| Sudden death has no clock of its own | A tie leans on kill rate, which is a slider. Pinned by a liveness test rather than left to chance | Unclaimed |
| ~~`BotController._nearest_cover()` scans every open cell, casting a ray each~~ | ~~Negligible on 24×14~~ **It was 478 µs a call against a 226 µs mean tick, every tick a bot retreated** | **PAID.** Ring walk outward from the bot: 63 µs. Retreat ticks went 536 µs → 233 µs |
| ~~`Tuning.get_value()` called per-tick at ~50 sites~~ | **Measured: 85.8 calls a tick at 0.34 µs = 29 µs, which is 0.17% of a 60 Hz frame** | **CLOSED, NOT PAID.** Caching in four files to save a sixth of one percent buys four new ways for a slider to go quietly dead (ADR-0021). `get_value()` now does one dictionary operation instead of two, which is the whole of it |
| ~~`SimWorld._free_bullet()` is a linear scan of 150~~ | **Measured: invisible.** ~34 shots/s across six fighters, ~75 field reads each | **CLOSED, NOT PAID.** A free list adds an invariant that can be corrupted, to save nothing |
| ~~Web export is a debug build (36 MB wasm)~~ | **The premise was false.** Pages serves it gzipped — measured on the wire at **10.2 MB**, not 36 — and the release export is *bigger* on disk (40.1 vs 38.5 MB), identical compressed | **CLOSED, NOT PAID.** Switching would also have deleted the DBG panel from the web channel, since it gates on `OS.is_debug_build()` |
| `GridPath.find_path()` is 357 µs a call and five bots repath in lockstep | The worst tick in a match (4.1 ms) is several A\* runs landing together. Already rate-limited to 2.5/s per bot, so it is a spike, not a leak | Unclaimed — staggering each bot's repath phase would spread it, but it changes bot timing and therefore behaviour, which this branch deliberately would not do |
| A missing data file degrades silently at runtime | `push_error` to a log nobody reads on a phone | Unclaimed; the CI gate makes it unreachable, which is not the same as impossible |

---

## 10. Invariants — break these and things fail quietly

1. `src/sim/**` never references `Input`, a `Node`, or anything in `src/view/`.
2. All damage flows through `SimWorld.apply_damage()`.
3. Anything spawned during combat comes from a pool.
4. No feel constant is a literal; it lives in `data/tuning_defaults.json`.
5. Every renderable keeps `prev_position` and is drawn interpolated.
6. Walls resolve before targets, with the arrow segment truncated first.
7. A new data file extension must be added to `include_filter` in
   `export_presets.cfg` — **both presets**.

Invariants 4 and 7 have automated enforcement (`test_tuning_keys.gd`,
`tools/verify_pack.sh`). The rest are conventions, enforced by review.

### The GDScript trap that has caused three bugs here

**Lambdas capture by value.** A counter assigned inside a signal handler
silently never updates outside it:

```gdscript
var hits := 0
world.hit.connect(func(...): hits += 1)   # WRONG — outer `hits` stays 0

var hits := []
world.hit.connect(func(...): hits.append(1))   # RIGHT — Arrays are references
```

This broke two tests and the screenshot tool's capture trigger. Use `Array` or
`Dictionary` when a closure must write to the enclosing scope.
