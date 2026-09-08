# ADR-0016: Nothing may reach further than the camera shows

**Status:** Accepted · M3.2

## Context

The first real playtest of the 3v3 build: *"the bots just shot at me from
out-of-screen and I'm dead in a second, it doesn't make any sense at all.
UNPLAYABLE."*

That is not a difficulty complaint. It is a **geometry bug**, and measurement
says so: over sixty seconds of a live match, **79% of the enemies that were in
range to hit the player were outside the visible rectangle.** Four out of five
threats were invisible.

Three numbers caused it, and the first is an arithmetic error of mine:

| | Was | Against a visible half-view of 356 × 200 |
|---|---|---|
| Arrow reach (`draw_max_speed` × `arrow_lifetime`) | 652 px | **1.8× the half-width** |
| `bot_preferred_range` | 380 px | bots held station *deliberately* just outside it |
| `bot_sight_range` | 1200 px | 3.4× |

In M3.1c I cut the arrow's reach to 652 px and checked it against the **711 px
visible width**, writing that "the truth now fits on screen". But the camera
follows the player, so the player is at the **centre** — the number that mattered
was the half-width, 356. The comparison was off by a factor of two and nothing
in the project could notice.

## Decision

**An arrow may not fly further than the shortest half-axis of the visible
rectangle**, and everything that reaches — auto-aim, bot sight, bot standoff —
is bounded by that same budget.

```
reach = draw_max_speed × arrow_lifetime  ≤  min(view_w, view_h) / 2
```

The **shortest** axis, not the width. The view is landscape (711 × 400), so the
vertical half is 200 px and is the binding constraint: at a 281 px reach a bot
directly above the player is out of frame and still lethal, which measurement put
at 7% of firing opportunities. Bounding on the tight axis takes that to **0%**,
and 0% is a guarantee rather than a small number.

The concrete budget: **reach 195 px**, auto-aim 210, bot sight 280, bot standoff
150.

### It is pinned by a test, and that is the actual decision

`tests/test_screen_budget.gd` asserts the inequality from the real
`ProjectSettings` viewport and the live `camera_zoom`. Every value involved is a
slider whose whole purpose is to be moved on a phone, so a tuning pass that fixes
the feel and quietly re-breaks the geometry is the **expected** failure, not an
unlikely one. Re-introducing the shipped 652 px reach now turns the suite red.

This is [ADR-0012](0012-verify-inside-the-artifact.md) applied to balance: the
artifact to inspect is the relationship between two numbers, and it had been
wrong in a shipped build for two milestones because nobody was checking it.

## Follow-up: the test measured the wrong thing (M3.2b)

This decision held. Its test did not.

`tests/test_screen_budget.gd` bounded `bot_sight_range` by **`reach × 1.5`** — an
invented proxy — instead of by the screen. 280 px passed against a 200 px
vertical half-view, so bots could acquire and shoot from off screen, and the very
next playtest reported it in the same words as the one that prompted this ADR.

The bound is the camera. Anything else is a number that happens to be nearby, and
a gate measuring the wrong thing is worse than no gate because it is also
reassuring. Fixed in [ADR-0018](0018-feedback-is-about-you.md)'s change, along
with a range check in `BotController._aim_and_fire()` — which had none, and would
fire at targets its arrows could not reach.

## Consequences

**Good:**
- If something can hit you, you can see it. Measured: 79% → 0%.
- The invariant survives future tuning passes instead of depending on my
  arithmetic.
- Fixture distances in tests and in `tools/screenshot.gd` now *derive* from the
  bow's real reach. Both had hard-coded distances that this change invalidated —
  one of which would have failed **silently**, asserting "the bot held fire"
  against a bot that had no target at all.

**Bad:**
- **The bow is now short: 195 px, about 3¼ cells.** This is a close-quarters
  brawler, and that is a real change in what the game is. If it feels cramped the
  honest fix is to zoom the camera OUT — which fights the M3.1c complaint that
  the cats were too small. `arrow_lifetime` and `camera_zoom` are the two dials,
  and the test names the trade rather than hiding it.
- Anything that deliberately out-ranges the screen later — an indirect-fire
  Longbow class lobbing over walls, say — needs an explicit exemption and a
  reason, not a quiet edit. That is the point.
