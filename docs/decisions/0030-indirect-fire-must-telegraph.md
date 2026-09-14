# ADR-0030: Indirect fire must telegraph, or it is the off-screen complaint again

**Status:** Accepted · M4.1

## Context

The third class is a lobber: a shell that flies **over walls** and damages an
area where it lands. It is the first mechanic in this game that makes anyone
move for a reason other than range — stone stops being an answer.

It also collides head-on with
[ADR-0016](0016-range-is-bounded-by-the-camera.md): *nothing may reach further
than the camera shows*. That rule exists because of a specific playtest:

> *"the bots just shot at me from out-of-screen and I'm dead in a second.
> UNPLAYABLE."*

A weapon that attacks what it cannot see is that complaint by construction. The
difference between an interesting class and an infuriating one is entirely
whether the target gets a warning.

## Decision

**A lobber may shoot over walls, and three properties make that fair. All three
are built in; none is a nice-to-have.**

**1. Reach still fits inside the half-view.** The class is bound by the same
per-class budget every other gun is, so a shell can never arrive from off
screen. It can only come from behind a wall that is *already visible*. The
existing loop in `test_screen_budget.gd` covers it with no new code, and a
lobber given 1.8× reach turns that test red.

**2. The shell is visible for its entire flight.** It clears the wall into open
view rather than passing through it, so the projectile is itself a warning. This
is why the gun is slow — `bullet_speed` 0.45× — rather than a fast mortar: a
shell nobody can see coming is a shell that teaches nothing.

**3. A landing ring is drawn on the ground, for everyone.** Not for the shooter
alone. `GameView._draw_incoming_shells()` draws under every arcing shell in the
air whoever fired it, and the ring TIGHTENS as the shell falls, so "about to
land" reads without counting. This is the property that turns an unavoidable hit
into a dodgeable one, and it is what Brawl Stars does for exactly this reason.

Between (2) and (3) there is no such thing as a blast nobody saw coming.

## The gesture made this easy, which is a sign it belongs

Under automatic fire this class would have been a stream of mortar rounds and
the telegraph would have meant nothing — the next shell was always 180 ms
behind the last.

[ADR-0031](0031-release-is-the-shot.md) changed the trigger to **hold to aim,
release to shoot**, and the landing ring the fairness argument demands is
exactly what the holding phase wants to draw anyway. The shooter lines up an arc
and watches where it will fall; everyone else sees the ring the moment it is in
the air. One mechanic serves both usability and fairness, which is usually the
sign a feature fits the game rather than being bolted to it.

The aim preview's reticle is therefore the **blast footprint** rather than a
fixed dot: aiming at a cluster, what you need to see before letting go is how
much ground the shell covers.

## Splash falls off, and a direct hit still detonates

Damage decays linearly to nothing at the rim, so where you stand *inside* the
blast matters. Flat damage across the circle would make position within it
meaningless, and position is most of what there is to play against a weapon you
cannot dodge by aiming.

A shell that strikes somebody on the way also detonates rather than applying its
bare damage — otherwise a direct hit would be *weaker* than a near miss, which
is the kind of rule that makes a game feel broken without anyone being able to
say why.

Both go through `SimWorld.apply_damage()`, the single funnel, so friendly fire,
ability charge and the hit event keep working with no new rules (ADR-0029).

## A bot must use it, or the mechanic does not exist

`BotController._aim_and_fire()` refuses to shoot when a wall is on the line —
correct for a flat round, and fatal for this class. An arcing gun skips that
gate. A bot that never uses its own mechanic teaches a child that the mechanic
does not work.

## Balance: a triangle, found over five sweeps

Measured with `tools/measure_matches.gd`, 20 seeded matches per match-up, all
six slots bot-driven:

|  | beats | loses to |
|---|---|---|
| lobber | ranger (+9 / −10) | skirmisher (−10 / +9) |
| skirmisher | lobber | — |
| ranger | — | lobber |

Ranger and Skirmisher are even (+3 / +1). Net standing **−7 / +10 / −1**, every
match-up inside 59/41.

A triangle is the shape worth having, and because both teams field **mirrored**
classes it cancels at team level — it is counterplay, not a match decided by the
draw.

Two corrections on the way, both the same mistake in different places: **a
number that had outlived its reason.**

- The Skirmisher stayed strongest through two trims. What finally worked was
  charging it in **sustain** rather than burst — reload 1.45×, so two shells
  then a 1.3 s refill. Its close-range lethality is the thing that was asked
  for, so that is the one part that should not pay.
- The Lobber opened beating the Ranger by +13. Splash **plus** ignoring cover is
  already a great deal of value; 0.85 damage on top was paying for it twice.

## And a fifth instance of the fixture bug

Giving the Ranger a 0.9× fire interval broke
`test_the_gun_will_not_fire_faster_than_its_interval`, which read the **global**
`fire_interval` while testing a specific gun — so "just short of the interval"
landed exactly on it. Four tests were fixed for this same reason in
`feat/classes` and this is the fifth.

`test_screen_budget.gd`'s time-to-kill gate had the same shape and was worse: it
checked `bullet_damage / fire_interval`, which with three classes describes a
weapon **nobody carries**. It now walks every class and guards the fastest real
one. A fixture that derives from a global measures the assumption, not the code.

## A sixth instance, in the telegraph itself

The landing ring tightens as the shell falls, and it computed that fraction
from **`_world.player.gun.lifetime()`** — the local player's gun — rather than
from the shell. That is correct only while every class flies for the same time,
which is exactly what this milestone ended.

A Ranger watching an enemy Lobber's shell divided a 0.33 s flight by its own
0.165 s reach, so the fraction clamped at 1.0 for the whole first half. The ring
sat at full width and only started closing once the shell was already halfway
down: **the telegraph degrading in precisely the case this ADR exists for**, in
the same file that argues for it, with nothing failing.

The fix is the rule `owner_team` and `arcing` already state on the same class —
**the projectile carries what the projectile needs**, because the shooter may be
dead before it lands. `Bullet.total_life` is set at launch and the view divides
by that.

Pinned by `test_a_shell_carries_its_own_flight_time`, which first asserts that
the two lifetimes genuinely differ (or it measures nothing) and then asserts
both readings: the shell's own says half the flight remains, and the borrowed
one says the shell has barely left the barrel.
