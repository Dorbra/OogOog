# ADR-0023: A bot that never stands still cannot be read, or hit

**Status:** Accepted · M3.3

## Context

> *"characters move around too fast"*

Asked which characters, the answer was **the enemies, not the player**. That
matters, because `move_speed` was already down to 150 px/s — 2.2 cat-lengths per
second, against Brawl Stars' ~2.4 — and pinned there by
`test_cats_move_at_a_speed_you_can_read`. The speed slider was not the problem
and turning it down again would have made the game sluggish to fix something it
was not causing.

`BotController._do_engage()` was:

```gdscript
var move := forward * radial + tangent * 0.85
```

applied on **every tick a target was visible**, with the sign reversing every
`bot_strafe_flip_time` = 1.2 s. A bot therefore never stopped moving, ever, and
changed direction roughly once a second. Six of those on a small screen read as
frantic darting at any speed.

The radial term made it worse rather than better: proportional to the distance
from the preferred range, it never quite reached zero, so even a bot that had
arrived went on creeping toward and away from you for the whole fight.

## Decision

**Strafing becomes a duty cycle, and arriving somewhere means stopping.**

- `bot_strafe_duty` = **0.6** — each cycle is part strafe, part stand still. The
  lateral term is simply not applied during the pause.
- `bot_strafe_weight` **0.85 → 0.55** — move toward a position rather than orbit
  one.
- `bot_strafe_flip_time` **1.2 → 2.2 s** — reverse half as often, and the sign
  flips at the top of a cycle so a bot commits to a direction for a whole
  segment instead of reversing mid-slide.
- `RANGE_DEADBAND` = 0.12 — inside 12% of its preferred range a bot stops
  closing. Without this the pause only stops the circling and the shuffling
  continues, so the bot is still never actually still.
- The cycle phase is seeded per bot from its existing RNG, so six of them do not
  stop and start as one body.

## The measurement that changed my mind about what this was worth

Ran 24 seeded matches with and without it, expecting a cosmetic change:

| | guns, bots darting | guns, bots fixed |
|---|---|---|
| mean kills | 11.42 | 12.17 |
| **shutouts (x–0)** | **5** | **1** |
| time to first kill | 14.8 s | 13.6 s |

Blowouts collapsed from five to one. A bot that pauses is readable **to the other
bots as well as to the player**, so fights resolve on position rather than on
whoever happened to be circling the right way. That was not the goal and is the
better half of the result.

## A gate I wrote, measured, and deleted

The obvious second assertion was a **reversal rate**: count direction changes per
second and require the shipped 2.2 s flip to beat the old 1.2 s. Measured, it
read **zero reversals at both settings** — it could not go red, at any value.

The cause is real: `_do_engage()`'s wall-avoidance flips `_strafe_sign` whenever
a strafe would walk into stone, and at the staged position it fires immediately
after every cycle wrap and flips the sign straight back. The metric was pinned by
the arena geometry under the test, not by the timer it claimed to measure.

Deleted, with the finding written into `tests/test_bots.gd` where the next person
to have the idea will read it. A gate that passes on the bug it was written for
is worse than no gate, because it is also reassuring — the same lesson as the
sight-range bound in [ADR-0016](0016-range-is-bounded-by-the-camera.md).

What ships instead is **the fraction of engaged ticks a bot is stationary**,
which is the thing the eye actually reports. It goes red on restoring either the
always-on lateral term or the missing deadband.

## Consequences

**Good:** the enemies read as fighting rather than twitching, matches are less
lopsided, and both halves are pinned by a gate that can fail.

**Bad:** a paused bot is easier to hit, which is part of why lethality rose. And
`bot_strafe_flip_time` is now unpinned by any test — the stillness fraction is
governed by the duty, not the flip rate — so it is a live slider with nothing
guarding it.
