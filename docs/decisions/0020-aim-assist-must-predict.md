# ADR-0020: Aim assist must predict, or it is worse than nothing

**Status:** Accepted · M3.2d

## Context

> *"התנועה לא כיפית ולא מרגישה טבעית, הדמויות מהירות והתנועה חדה מדי, אין סיכוי
> לכוון ולפגוע ככה... התנועה לא מהירה מדי אבל כן יש חשיבות לAim skill שלך"*
>
> "The movement isn't fun and doesn't feel natural, the characters are fast and
> the movement is too sharp, there's no chance to aim and hit like this...
> movement not too fast, but your aim skill does matter."

Two complaints. The speed one was a number. The aiming one was a bug, and it was
mine.

### The bug

`SimWorld._try_fire()`'s snap branch and `_apply_aim_assist()` both computed:

```gdscript
(target.position - shooter.position).normalized()
```

**Where the target is.** Not where it is going. At the shipped 250 px/s walk
against a 780 px/s arrow, a shot aimed at a running cat's current position can
only connect inside **90 px** — while `autoaim_radius` was **235**.

So past a third of its own radius the assist did not merely fail to help. A
player who led the shot correctly, and was therefore pointing *away* from the
cat, had their shot bent back onto the cat and onto a miss. **The auto-aim was
actively worse than no auto-aim.**

`BotController._lead()` has done proper two-pass intercept prediction since
`feat/bots`. The bots led their targets. The player never did, in either firing
path. One idea, two implementations, and only one of them right.

## Decision

**One intercept solver, `src/sim/aim.gd`, called by every producer of an
`InputCommand`.**

```gdscript
Aim.intercept(from, projectile_speed, target_pos, target_vel, lead, fallback)
```

`lead` scales the prediction, and `lead = 0` reproduces aim-at-where-it-is-now
exactly — which is what makes the bots' difficulty slider a dial on the same
function, and what makes extracting it from `BotController` provably
behaviour-preserving.

| Caller | `lead` | Why |
|---|---|---|
| Snap (tap) shot | 1.0, unbounded | The accessible option. A five-year-old taps, and a tap that cannot hit a moving cat is not accessible |
| Aimed (drag) shot | 1.0, **clamped to `aim_assist_deg`** | Closes a near miss. Does not lead for you |
| `BotController` | `bot_lead_factor × bot_skill` | Unchanged |

### The clamp is the design, not an implementation detail

The first version gated admission on a 4° cone and then **snapped onto the
intercept**. The lead a player owes at these speeds is about 16°, so a 4° gate
granting a 16° turn is a lock-on: point at the cat, and the game does all of the
leading. Aim skill would have been "can you point at a cat", which is not the
skill the request was about.

Bounded, `aim_assist_deg` means one thing — **how far the game may bend your
shot** — and leading stays the player's job.

## The measurement that overturned the plan

The plan for this change was reasoned, and it was wrong twice. Both errors were
caught by firing real arrows through the real tick loop.

**First: "the sprite is 20% wider than the hurtbox."** `CatView` scales the
sprite to `radius * 2.4`, arrows tested `radius`, so a shot clipping the visible
cat missed. A `hit_radius_mult` was added to close the gap.

It was nonsense. `cat_body.svg` is a 128 px canvas that is mostly transparent
margin: the drawn cat is **36 px wide** against a **58 px** hurtbox. The hurtbox
was already **1.6×** the visible cat. Widening it further made an unled shot
connect at *every* range in the book — leading became worth nothing at all.
Reverted.

**Second: the angle arithmetic.** Comparing the lead angle against the angle a
cat subtends said leading became necessary past 75% of the bow's range. Fired for
real, an unled shot hit at 100% of range. The swept collision test measures the
arrow's **closest approach**, not where it ends up, and a proxy that ignores that
is off by a quarter of the range.

So the gate is no longer an angle. `tests/test_aim.gd` fires an arrow at a cat
that is actually running and asserts what happened:

- inside 40% of reach, pointing straight at it **hits** — the game is playable
  for someone who just points;
- at `bot_preferred_range`, pointing straight at it **misses**, and a properly
  led shot **hits** — aim skill matters, and it is learnable.

`tools/measure_matches.gd` reports the same number for the whole build: *unled
shots hit within N% of reach*. It is 65%.

## Consequences

**Good:**
- The player and the bots now aim through the same function, so the class of bug
  — one of them silently better than the other — cannot recur.
- The aim preview calls `assisted_aim()`, so the dotted line is the shot that
  will be fired. It was already up to 8° out before this change.
- Matches resolve far better as a side effect: mean kills 2.62 → 6.08 over 24
  seeded matches, first kill at 48.8 s → 16.4 s.

**Bad:**
- `assisted_aim()` is public purely so the view can ask what the shot will be.
  That is a seam from `src/view/` into `src/sim/`, in the read-only direction
  ADR-0003 allows, but it is coupling and it should be named.
- The preview change cannot be seen in a render capture: the combat capture's
  target is stationary by design (ADR-0012's determinism requirement), and
  against a stationary target the intercept *is* the straight line. Verified by
  shared code and unit tests, not by a picture.

## The general lesson

[ADR-0016](0016-range-is-bounded-by-the-camera.md) already said a gate must
measure the thing rather than a number that happens to be nearby. This is the
third and fourth time that has bitten, in one branch:

**A proxy you can compute is not the quantity you care about.** The lead angle
was computable and wrong. The sprite's texture size was computable and wrong.
Firing the arrow was neither, and it was right both times.
