# ADR-0031: Hold to aim, release to shoot — and each bullet counts

**Status:** Accepted · M4.1 · **supersedes the automatic fire in [ADR-0026](0026-firing-is-a-state.md)**

## Context

> *"The Player wants to always keep the right stick clicked in order to aim and
> be ready, and when you want to shoot you just release! Just like Brawlstars
> mechanics! So we get rid of the fast and auto fire, but make each bullet
> count, so no longer spamming shots but aiming and hitting is the key for
> winning."*

The gun has been automatic since ADR-0026: hold the right thumb and it fired
continuously at `fire_interval`, and the magazine plus the reload were the only
brakes. That was itself a reversal of the release-to-fire gesture that shipped
one milestone earlier, and it was asked for in the same words this is.

The reason it did not survive contact is worth writing down, because it is a
property of the mechanic rather than of the numbers: **hold-to-fire makes
bullets cheap.** When the optimal input is "hold the trigger and sweep", the
decision the player makes several times a second is *where to point*, not
*when to shoot* — and missing costs nothing, because the next bullet is 180 ms
away. Aim stopped deciding fights and volume decided them.

## Decision

**A thumb going down aims. A thumb coming up shoots, once.**

- Holding costs nothing and can last as long as you like. The line of fire
  brightens, so a held thumb is visibly a loaded shot rather than a stream.
- Releasing fires exactly one bullet.
- `fire_interval` becomes a **floor** (0.5 s), not a cadence. It exists only so
  a frantic tapper cannot turn this back into spam; your thumb sets the rhythm.
- Each bullet is worth far more: damage 40 → **65**, so 200 hp is **3.1 hits**.
  The magazine drops 5 → 3 and the reload goes 0.55 → 0.9 s, which makes running
  dry an event you plan around rather than a hiccup.

## What survives from ADR-0026, and what does not

**Does not survive:** automatic fire, and `fire` as a state that stays true for
as long as a trigger is held.

**Survives, and is the part that actually mattered:** the frame-rate trap.
ADR-0026 was written because a signal emitted once per *rendered frame* drove a
simulation ticking at a fixed 60 Hz through a one-tick pending flag — two clocks
agreeing by accident, so the shot count depended on the frame rate.

Release-to-fire is exactly the shape that could reintroduce it, and does not:
`TouchControls` records the release as an **edge**, and `SimWorld` consumes it at
the tick boundary through `take_fire()`. One release is one bullet at 50 fps and
at 120. That is the same consume-once pattern the ability button already uses,
and it is the reason `fire` can go back to meaning "on this tick" without the
bug coming back with it.

## The tap comes back, and this time it is not a spray

A press-and-release that never carried a direction hands the whole shot to the
game, which leads the nearest visible enemy through the one shared
`Aim.intercept()` solver ([ADR-0020](0020-aim-assist-must-predict.md)).

It was deleted when the gun went automatic, and correctly: a tap that fires into
a continuous stream is just a worse way to hold the trigger. With one deliberate
bullet per release it is the shot a five-year-old can actually land, which is
what [ADR-0013](0013-audience-is-a-family.md) asks for.

**One threshold decides both questions.** `aim_min_drag` says whether a drag
moved the aim *and* whether the release was a tap. Two numbers for one question
is what produced the dead band ADR-0024 was written about, where a gesture was
classified as aimed while the aim it fired along had never been updated.

## Balance: the shotgun had to give something back

Measured with `tools/measure_matches.gd` over 24 seeded matches per match-up,
all six slots bot-driven. The cadence change alone made the Skirmisher
**overpowered — 60–63% of the kills in both directions.**

The cause was not the shotgun; it was a stale number. Its 1.55× health was set
in `feat/classes` to pay for crossing 107 px of open ground under **222 DPS** of
Ranger fire. At the new cadence that same walk costs **130 DPS**, so the
compensation had outlived the problem it was compensating for.

| | before | after |
|---|---|---|
| `health` | 1.55 | **1.2** |
| `damage` | 0.42 | **0.48** |

That trade is the ask, precisely: **more lethal up close** — 94 damage a
connecting fan, 2.1 hits to a kill inside 74 px — paid for by no longer being a
tank as well. Beyond its fan's spread only the centre pellet lands, which is 31
damage and 6.4 hits.

Final: cross match-ups **46% and 55%**, against mirror baselines of 48% and
50% — about a 3-point edge to the Skirmisher, which is a match-up rather than a
class to avoid.

**The honest limit on that number:** it is measured bot against bot, and a bot
fires on a timer while a person has to aim and let go. Whether a shotgun is
*easier to use well with a thumb* than a rifle is not something this table can
answer. Only thumbs can.
