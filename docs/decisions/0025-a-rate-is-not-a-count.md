# ADR-0025: A rate is not a count — the kill cap was inside my own metric

**Status:** Accepted · M3.5

## Context

> *"shooting should feel faster and I would be able to 'spam' shots - also
> increase the 5 bullets to 10. reduce the TTK a bit, I think 3-5 good shots are
> enough for a kill"*

Two asks that multiply: faster fire **times** fewer hits to kill. So this got
swept rather than reasoned about, using `tools/measure_matches.gd` across three
fire intervals and three damage values.

## The mistake, which nearly shipped

The first grid reported **mean kills per match**, and it was not monotonic:

```
fire 0.35  dmg 50  ->  21.25 kills
fire 0.18  dmg 40  ->  22.81 kills   <- apparent peak
fire 0.18  dmg 50  ->  21.31 kills   <- MORE damage, FEWER kills
```

I read that as a real effect and had a mechanism ready for it: past a point the
extra damage is wasted as overkill on a target that was already dying, so it
buys nothing but respawn downtime. Plausible, tidy, and wrong.

**`match_target_kills` was 14 in every row.** A match that reaches the kill cap
*ends*, and a match that ends stops accumulating kills. So the more lethal a
configuration was, the sooner it hit the cap, and the fewer total kills it
recorded. My independent variable was shortening the window my dependent
variable was counted in.

The tell was there and I walked past it: raising the cap on a fixed
configuration moved "mean kills" from 22.5 to 32.9 to 39.4 to 42.1. A metric
that triples when you change a rule about *ending* is not measuring lethality.

Re-run with the cap disabled so every match runs the full 120 s, the grid is
monotonic in both axes, as physics demands:

```
                          kills   mean life   deaths/fighter
fire 0.35  dmg 28         21.06      34.2s        3.5
fire 0.18  dmg 40         42.88      16.8s        7.1
fire 0.18  dmg 50         49.50      14.5s        8.2
```

**The "overkill" finding did not exist.** It was an artifact with a story
attached, and the story is what made it dangerous — it was the kind of finding
that gets quoted in a PR description and believed.

### The rule

**Never compare a per-match total across configurations that change how long a
match lasts.** Measure a rate, or hold the terminating condition constant.
`measure_matches.gd` now carries this warning in its header, because the tool
makes the wrong comparison the easy one.

## Decision

Settled with the user, presented with the measured cost of each option:

| Key | From | To | |
|---|---|---|---|
| `fire_interval` | 0.35 | **0.18** | 5.6 shots/s in a burst |
| `magazine_size` | 5 | **10** | 1.8 s of continuous fire |
| `reload_time` | 1.1 | **0.55** | 1.8 shots/s sustained |
| `bullet_damage` | 28 | **40** | 5.0 hits, 0.90 s of perfect fire |
| `match_target_kills` | 14 | **35** | the clock decides 23 of 24 again |

Measured end state: **42.5 mean kills, a cat lives 16.8 s, ~7 deaths each** —
**3.2× the lethality on `main`**, which is what was asked for after being shown
that number.

`reload_time` was not requested and is called out because it is the single
biggest lever in the set: the magazine and refill change **alone**, with damage
and fire rate untouched, takes kills 13.3 → 21.1. Ten rounds is not a
convenience; without the faster refill the spam stops after one magazine.

## Two gates this broke, and what replaced them

**`test_a_fighter_survives_more_than_a_moment` was a hit-count floor** — "at
least four hits". When `fire_interval` fell 0.35 → 0.18, wall-clock time to kill
went 2.50 s → 0.90 s while the hit count barely moved, so the gate went on
passing while the thing it protects against got two and a half times worse. It
now pins **both**: at least 3 hits (the user's own floor), and
`hits × fire_interval ≥ 0.6 s`. Setting the interval to the slider's minimum
turns the second one red while the first still passes — which is precisely the
gap that existed.

**The bot cheat guard hard-coded "at most 4 shots a second"**, correct for the
0.35 s interval it was written against and wrong the moment the interval moved.
It derives the bound from `fire_interval` now. A guard that must be edited
whenever the gun changes is a guard that will one day be edited to whatever the
bot happens to be doing.

## A visual consequence, caught in a capture

Ammo pips were a flat 9 px each, so the **row** grew with the magazine: 57 px at
five rounds against a 58 px cat, 117 px at ten — a bar twice as wide as the
animal it belongs to. Pips shrink to fit a fixed span now, pinned by
`GameView.magazine_pip_width()` across the whole 1–12 slider range rather than
at the one value that happens to ship.

## Consequences

**Good:** the gun feels the way it was asked to feel, and every number behind it
was measured rather than argued.

**Bad:** 7 deaths per fighter per match is a lot, and whether that reads as
exciting or as chaos cannot be answered from here. `fire_interval` and
`bullet_damage` are the two dials, both live under DBG.

**Unknown:** this is bots against bots at `bot_skill` 0.2. The player has a
leading auto-aim and a flat bullet, so the player kills faster than this
predicts and dies at roughly the measured rate. The asymmetry is not modelled.
