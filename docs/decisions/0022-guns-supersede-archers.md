# ADR-0022: Guns supersede archers; the draw curve is deleted, not tuned

**Status:** Accepted · M3.3 · supersedes the "Archers, not guns" decision, which
was never an ADR — it lived in [GAME_DESIGN.md](../GAME_DESIGN.md) and in the
original plan, which is part of why it survived unexamined for so long

## Context

> *"the gameplay is still bad and feels weird — characters move around too fast;
> the Arrow shooting is sluggish and cant be expected, lets change back to
> GUNS! with a clear line-of-fire"*

Archers were chosen because the gesture and the fiction were the same action:
hold to draw, release to loose, and one number — draw strength — replaced the
whole spread/recoil/accuracy-cone stack a gun would need. That reasoning was
sound and it produced a weapon nobody enjoyed using.

Measured on `main` at the time of the complaint:

```
hold before any shot leaves   450 ms   (draw_time_full)
flight to maximum range       440 ms
required lead angle           16.1 deg at every range
drift during flight           66 px = 1.14 cat widths
```

Nearly a second between deciding to shoot and finding out, and a lead bigger
than the target. "Sluggish and can't be expected" is an exact description.

### The part that was mine

`fix/movement` planned to take the required lead from 17.8° to **10.9°** by
halving movement speed and leaving the bow alone. During implementation I also
cut `draw_max_speed` 780 → 520 and raised `arrow_lifetime` 0.29 → 0.44,
reasoning that a longer flight makes leading matter more — the user had asked for
aim skill to matter. Shipped, that measured **16.1°**. I moved a number the plan
did not contain, in the opposite direction to the plan's own arithmetic, and made
the complaint worse.

## Decision

**A gun. The draw curve is deleted rather than turned down.**

| | from | to |
|---|---|---|
| `bullet_speed` | 520 | **1400** |
| `bullet_lifetime` | 0.44 | **0.165** (reach 231, inside the 248 px half-view) |
| hold before firing | 450 ms | **none** — the release is the shot |
| `fire_interval` | — | **0.35 s**, enforced inside `Gun` |
| required lead | 16.1° | **6.1°**, against a cat subtending 7.2° |

Point at a cat and the bullet arrives where you pointed, at every range. That is
the "clear line of fire" that was asked for, stated as arithmetic.

**Tap to fire**, chosen over hold-to-fire: a press starts a gesture and fires
nothing, and the release fires one round — in the drag direction if you dragged,
auto-aimed and leading if you did not. `auto_repeat` survives as a slider
defaulting to **0**.

Three supporting choices, each of which could have gone the other way:

- **The rate limit lives in `Gun`, not in the input layer.** The player and the
  bots are then gated by the same code, which is what keeps "a bot cannot
  out-shoot you" true. It also means a fast tapper has shots *refused* rather
  than queued — queueing would turn quick fingers back into lag.
- **Classification is on drag distance alone.** A hold threshold used to be half
  of it, so a player lining up a careful shot had it silently reclassified as an
  auto-aimed tap for taking too long.
- **No deviation at all.** Random spread on top of a fast flat bullet is exactly
  the "can't be expected" being removed.

## What this costs, stated plainly

**Draw strength was the game's only shooting depth.** Every shot is now
identical, and nothing yet distinguishes one from another. That is a real loss,
not a simplification.

The replacement is **class asymmetry in `feat/classes` (M3.4)** — a shotgun
spread, a multi-shot, a lobbed arc — which is where Brawl Stars keeps its variety
and always was the plan. Until that lands the shooting is deliberately plain.
If M3.4 slips, this is the debt that comes due.

## An invariant the user overruled

`fix/movement` added a **floor** to `tests/test_aim.gd`: an unled shot must MISS
at the range bots hold station. "Aim skill has to matter", encoded as a test.

A 1400 px/s bullet fails it, and keeping it would have meant slowing the bullet
back down to protect a belief the person playing the game had already rejected.
So it is replaced rather than loosened, by the positive form of the same
question: **an unled shot must HIT, at 40%, 70% and 95% of reach**, fired through
the real tick loop. The mirror — that a properly led shot also connects — stays,
so neither can pass vacuously.

A test may encode a design decision. When the decision changes, the test changes
with it, and the change gets written down instead of being quietly deleted.

## Consequences

**Good:**
- Firing is immediate and the line of fire is readable. Measured, an unled shot
  connects at every range in the book.
- One weapon path for players and bots, with the rate limit in shared code.

**Bad:**
- Every shot is the same shot until M3.4.
- Lethality roughly doubled — 24 seeded matches went from a mean of 6.08 kills to
  **12.17** — because shots that used to miss now land. `match_target_kills` went
  10 → 14 to keep the clock deciding, and `test_a_fighter_survives_more_than_a_moment`
  (≥ 4 hits to a kill; currently 7.1) is the guard against "dead in a second"
  returning.
- `Bow`/`Arrow` became `Gun`/`Bullet` across sim, view, tools and tests. A large
  mechanical diff, taken deliberately: a gun that fires "arrows" in code is how a
  codebase starts lying about itself.
