# ADR-0024: The aim outlives the shot, and it is a fact about the fighter

**Status:** Accepted · M3.4

## Context

> *"Shooting supposed to be same as Brawlstars — where you can click & Drag the
> Aim, and only when released it shoots, that way the Player can keep a
> line-of-fire, and not 'reset' after every shoot... Think about FPS games on
> Mobile"*

The gesture shipped in [ADR-0022](0022-guns-supersede-archers.md) is
click-drag-release, which is what was asked for. What happened *after* the
release was wrong, and reading the code turned up **three** faults in the same
gesture rather than the one that was reported.

### 1. The reset

```gdscript
# touch_controls.gd::_release_finger
aim_vector = Vector2.ZERO

# fighter.gd::tick
if cmd.aim != Vector2.ZERO:            facing = cmd.aim
elif velocity.length_squared() > 1.0:  facing = velocity.normalized()
```

Release the thumb, the aim goes to zero, and `facing` falls through to the
**movement** direction. `CatView` draws the gun along `facing`, so the barrel
visibly swung away the instant you fired. There was no line of fire to keep.

### 2. A dead band between two thresholds nobody had reconciled

`snap_max_drag` was **26 px** and `aim_min_drag` was **40 px**. `_emit_shot()`
called anything over 26 an aimed shot; `_update_aim_direction()` refused to move
the aim under 40. A drag landing in that gap fired as an aimed shot along an aim
nothing had updated and the preview had never drawn.

### 3. The preview lying again — mine, from the PR that removed the charge

The dotted line follows the **smoothed** `aim_vector` (`aim_smoothing` 16, about
100 ms of lag). `_emit_shot()` ignored it and fired the **raw final drag**. Flick
and release, and the bullet went somewhere the line had never pointed. That is
precisely [ADR-0019](0019-appearance-is-not-behaviour.md), reintroduced two PRs
after it was written.

## Decision

**Facing is owned by the aim, permanently, from the first aim onward.**

- Walking never reclaims facing. Settled with the user against the alternatives
  of a timed hold and of Brawl Stars' own behaviour (which turns you when you
  move, and *is* the reset being complained about).
- Before the first aim, facing still follows travel — otherwise six cats
  moonwalk out of their spawns at the start of a round.
- **`SimWorld._try_fire()` sets `shooter.facing` to the direction fired.** A tap
  carries `Vector2.ZERO` because the world auto-aims it, so without this the
  firing tick falls through to the movement branch and the reset survives on the
  one shot a five-year-old actually uses.
- **One threshold.** `aim_min_drag` is deleted; `snap_max_drag` decides both
  "is this a tap" and "does this move the aim", so the dead band is
  unrepresentable rather than merely fixed.
- **The shot goes along `aim_vector`** — the vector the preview drew — not the
  raw drag. Preview and shot are the same value rather than two values that
  agree.
- **The line stays on screen, dimmed** (`aim_line_idle_alpha`), with the assist
  and the wall cast applied in both states: a faint line that lies is worse than
  no faint line.

## The part the plan got wrong

The plan put the persistence in `TouchControls` — just stop zeroing
`aim_vector`. That works for the player and **leaves the reset latent in the
simulation for every other producer**, the network being the next one. It also
makes the rule untestable without a thumb: the first version of
`test_the_aim_survives_the_shot_and_walking_does_not_move_it` failed, because
driving `SimWorld` directly with a cleared `InputCommand` still spun the cat.

So the rule moved into `Fighter` as `_has_aimed`. Whether your facing survives a
shot is a fact about a fighter, not about one input device — the same reasoning
as [ADR-0015](0015-concealment-is-a-sim-rule.md), where concealment stopped being
a fade in the view and became something the simulation knows.

**The failing test is what moved it.** Written against the behaviour the user
described rather than against the fix I had planned, it rejected the fix.

## Consequences

**Good:**
- The line of fire persists, is visible, and is the shot that will actually be
  fired. Five gates cover it, each red when its fault is restored.
- The rule holds for bots and for the future network producer for free.

**Bad:**
- A cat that has aimed once never faces its movement again, so a player who
  aims and then walks a long way is running sideways. That is twin-stick
  convention and it is what was asked for, but it is a real visual cost.
- `aim_smoothing` now decides where shots go, not just where the line is drawn.
  At 16 a flick-and-release fires up to ~100 ms behind the thumb — honest,
  because the line showed exactly that, but it is a feel value that has just
  become load-bearing and nothing pins it.

## Verification

`tests/test_gun.gd` — the aim survives a shot and a full second of walking the
other way; a tap faces the target it auto-aimed at; the fired vector equals the
previewed vector during a mid-smoothing flick (with the mirror, that the flick
really was mid-smoothing, so it cannot pass vacuously); no drag length between
10 px and 120 px fires along an aim it never set; and the line is still drawn,
dimmer, with no thumb down.

That last one goes through a static `GameView.aim_line_strength()` rather than a
rendered frame, because **no render mode has a thumb on the screen** — a capture
cannot tell "drawn dim" from "not drawn". The choice was a testable function or
no gate at all.

24 seeded matches re-run: **13.29 mean kills, 1 of 24 decided by the kill
target — identical to the `feat/guns` baseline.** Predicted flat, because bots
set an aim every tick and never had the reset; measured flat.
