# ADR-0026: The gun is automatic, and firing is a state rather than an event

**Status:** Accepted · M3.6 · supersedes the tap-to-fire gesture in
[ADR-0022](0022-guns-supersede-archers.md)

## Context

> *"טוב יש שיפור אבל עדיין לא אוהב את איך שהירי מרגיש, לדעתי נעבור למצב אוטומט,
> 5 כדורים, הttk כרגע מרגיש יותר טוב. תבדוק את המשחק Tacticool, הוא עושה את
> היריות והaim ממש טוב"*
>
> "Better, but I still don't like how the shooting feels. Let's switch to
> automatic, 5 rounds. The TTK feels better now. Look at Tacticool — it does the
> shooting and the aim really well."

This is the **third** firing model. A charge came first (450 ms of thumb before
anything left the bow — "sluggish"), then tap-to-fire, one round per
press-release. Neither felt right in the hand.

### What Tacticool actually does, and why we did not copy it

Looked it up rather than assumed. Tacticool has **no trigger at all**: you swipe
the right side to aim, and the weapon fires by itself when an enemy enters the
reticle. Aiming *is* the whole action.

That was put to the user as the recommended option and **rejected in favour of
plain hold-to-fire**, which is the right call for a reason specific to this game:
**firing reveals you.** `Fighter.reveal_timer` exists so an ambusher in a bush
cannot shoot with impunity ([ADR-0015](0015-concealment-is-a-sim-rule.md)). A gun
that fires by itself whenever anyone crosses the line would reveal you
constantly and delete the ambush mechanic outright. Holding the thumb keeps
"engage" and "hold fire and stay hidden" as separate, deliberate acts.

## Decision

**Hold the right half and the cat fires, continuously, along your aim. Let go
and it stops.** `magazine_size` 10 → 5, as asked. Damage and fire interval
untouched — the TTK was reported as good.

Three things are **deleted**, not disabled:

- **The tap shot.** A quick press-release used to fire one auto-aimed, leading
  round at the nearest enemy — the five-year-old's move. The user chose to drop
  it so every bullet comes out of one path. The leading assist survives inside
  `aim_assist_deg`, so a held burst is still helped toward the intercept.
- **The `auto_repeat` toggle.** The gun *is* automatic now. An option nobody
  picks is a second code path nobody tests.
- **`snap_max_drag`**, renamed to `aim_min_drag`. It stopped meaning "is this a
  tap" and now only means "is this drag real, or thumb noise". Keeping the old
  name would have left the code describing a mechanic that no longer exists.

## The structural half, which is the part worth keeping

**Firing stopped being an event.**

It used to be a `shot_fired` signal, emitted from `TouchControls`, caught by
`main.gd`, stashed in a `_pending_shot` flag, and consumed by the next
simulation tick. That relay existed because a shot *was* a discrete moment. With
a held trigger it is a **state**, and the state is read directly:

```gdscript
_cmd.fire = controls.is_firing
```

That deletes the signal, the three pending fields, and the handler — and with
them a real defect nobody had hit yet. The signal fired **once per rendered
frame** while the simulation ticks at a **fixed 60 Hz**. On a phone running at
50 or 120 fps those two clocks disagree, and the fire rate would have drifted
with the frame rate. It never showed up because `Gun.consume()`'s cooldown
happened to mask it.

**A state read once per tick cannot drift.** The frame rate stops being an input
to the simulation, which is the whole point of ADR-0003's sim/view split — the
relay had quietly punched a hole in it.

## Measured

24 seeded matches, kill cap disabled so match length cannot confound the count
([ADR-0025](0025-a-rate-is-not-a-count.md)):

| | kills | mean life |
|---|---|---|
| magazine 10 | 42.88 | 16.8 s |
| **magazine 5** | **40.75** | **17.7 s** |

Only −5%: the magazine sets burst length, while sustained fire is limited by
`reload_time` either way.

**This understates the player's change and is worth stating plainly.** Bots set
`cmd.fire` directly and were always "automatic", so the simulation cannot see
the difference between a human tapping (perhaps 3–4 a second) and a human
holding (5.6 a second). The player's real rate of fire goes *up* despite the
smaller magazine. Only thumbs can price that.

## Three test bugs on the way through

Recorded because all three were mine, and one is a trap this repository already
documents:

1. **A GDScript lambda captures by value.** `shots += 1` inside a signal handler
   increments a copy and reports zero forever. `test_bots.gd` carries a comment
   warning about exactly this, and I wrote it again anyway.
2. **A magazine bound that ignored the reload.** I asserted a held trigger could
   not fire more than `capacity` rounds; over one second at a 0.55 s reload it
   legitimately fires one more. The bound is derived now, reload included.
3. **An assertion comparing two angles with no fixed relationship.** It failed
   on correct code. Restated as a distance to the true intercept.

## Consequences

**Good:** one firing path, one clock, three fewer moving parts, and the
sim/view boundary is honest again.

**Bad:** the five-year-old lost the tap that aimed itself. The narrow leading
assist is what remains, and if the youngest player struggles, `aim_assist_deg`
is the dial — a wider cone gives back most of what the tap did.
