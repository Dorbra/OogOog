# ADR-0028: A class is a multiplier, not a stat block

**Status:** Accepted · M4

## Context

Every shot in the game was the same shot. The draw curve went with the bow
([ADR-0022](0022-guns-supersede-archers.md)) and the tap shot went with
automatic fire ([ADR-0026](0026-firing-is-a-state.md)), and neither was
replaced. Measured, an unled shot hits at **100% of range**, so there was not
even a leading skill left — `GAME_DESIGN.md` says so outright and names class
asymmetry as the debt.

The obvious implementation is a stat block per class: each one carries its own
damage, fire rate, range, magazine.

## Decision

**A class carries MULTIPLIERS over the existing global tuning keys.** It never
carries a value of its own.

The reason is not tidiness, it is the on-device workflow. Nobody on this project
can run the game on a desktop, so every feel constant is a live slider and "what
should this number be" is answered with thumbs
([ADR-0004](0004-runtime-tuning.md)). Per-class absolutes would take the DBG
panel from 63 sliders to roughly 190, and — the part that actually kills it —
**there would no longer be a "damage" slider to drag.** There would be three,
and pulling on any one of them would tell you about a third of the game.

With multipliers, every slider still moves the whole game and a class says only
how it differs. `data/classes.json` holds the table; `Gun` multiplies.

## Three rules that fell out of building it

**The fan is deterministic.** A spread class fires its pellets at fixed angles
across the arc, never randomised. Random spread on a fast flat bullet is exactly
the *"cant be expected"* that got the bow deleted, and it would make every
headless assertion about where a shot goes unrepeatable as well. Point blank all
three connect; at range they open. Same shot, same result, every time.

**A bot fights at its gun's EFFECTIVE range, not its reach.** This one cost four
attempts. `bot_preferred_range` scaled by the class's reach put a Skirmisher at
105 px — and a 46° fan opens past a 29 px cat at 74 px, so it stood exactly
where its shotgun stopped being a shotgun and got shot by Rangers the whole
time. `Gun.effective_range()` is now the distance at which the *whole* shot
lands, and that is where bots stand.

**A fixture that derives from a global key measures the assumption, not the
code.** Four tests broke when classes landed, and every one of them was right to
break: they staged a bot at `bot_preferred_range + 60`, bounded its fire rate by
the global `fire_interval`, computed reach as `bullet_speed × bullet_lifetime`.
Those were all the same number as the bot's own while there was one gun. Each
now asks the bot under test.

## The measurement, because the design was wrong four times

`tools/measure_matches.gd` plays every class against every class with all six
slots bot-driven and reports kill share. The Skirmisher opened at **30–33%**
against a Ranger team — not a match-up, a class that did not work.

| change | why |
|---|---|
| `spread_deg` 11 → **46** | At 11° the outer pellets stayed inside a cat to maximum range. The spread was decoration. |
| `Gun.effective_range()` | The rule above. Bots fought where their gun did not work. |
| `fire_interval` → **0.8** | Rapid, as the class was always described. |
| `health` → **1.55** | The one that worked. Crossing 107 px to reach its own effective range costs 0.6 s under 222 DPS. |

Two multipliers the plan never contained — `move` and `health` — had to be
added, because a short-ranged class has to survive the walk in and then close.

**Final: cross match-ups 48% and 52%, against mirror baselines of 47% and 50%.**

Two measurement bugs were found on the way, both in the tool rather than the
game, and both worth recording because they are the same species as
[ADR-0025](0025-a-rate-is-not-a-count.md):

1. The table was confounded by the idle player slot, whose handicap depends on
   the class it would have been — so the rows could not be compared with each
   other or with the mirrors.
2. Driving that slot by assigning `fighters[0]` a controller does **nothing**.
   `SimWorld.tick()` reads the passed-in command for `player` and never consults
   its controller. Four rows identical to the last kill are what gave it away.

## Consequences

- Adding the lobber next PR is a row in `classes.json` plus whatever new
  behaviour it genuinely needs — not a fourth copy of every number.
- `test_screen_budget.gd` now bounds **every class's** reach by the half-view
  rather than the base key, which is
  [ADR-0016](0016-range-is-bounded-by-the-camera.md) applied to a world with
  more than one gun.
- The class silhouette is drawn on **every** cat, not just the player's. It is
  the only thing on screen that says what an enemy is carrying: there is no text
  anywhere in this game and colour already means team.
