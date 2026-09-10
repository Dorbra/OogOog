# ADR-0029: Abilities charge from damage dealt, not from a clock

**Status:** Accepted · M4

## Context

Each class carries one ability — a dash for the Ranger, caltrops for the
Skirmisher. Something has to decide when you get to use it. The default is a
cooldown: press it, wait N seconds, press it again.

## Decision

**Charge accrues from damage DEALT.** No timer anywhere.

A cooldown pays you for waiting. In a two-minute match with out-of-combat regen
already rewarding disengagement, a second mechanic that rewards not fighting is
the wrong pull — the design has spent two milestones getting matches to resolve
at all ([ADR-0025](0025-a-rate-is-not-a-count.md) and the regen sweep before
it). Damage-charging pays you for fighting, which is where the match needs
players to be, and it is what Brawl Stars built its Super on.

`Fighter.charge` runs 0 to 1 and fills at `ability_charge_damage` (400 hp — ten
Ranger hits) per bar.

## The rules, and why each exists

**Paid inside `SimWorld.apply_damage()`, the single funnel.** Every damage path
already goes through it — bullets, caltrops, whatever the lobber brings. Paying
at each call site instead guarantees a future damage source that silently earns
nothing, and nobody would notice for a milestone.

**Never for friendly fire, and never for self-harm.** An ability you can charge
by shooting your own team is not an ability, it is a chore, and a five-year-old
would never discover the trick while a ten-year-old certainly would.

**Capped, never banked.** Overkill on a dying target must not buy the *next*
ability early, and a Skirmisher landing three pellets on one trigger pull must
not be paid three times for it.

**Charge survives death.** Deliberate. Losing it on death punishes the player
who is already losing, hardest at the moment they need a comeback most — the
opposite of *"competitive but not punishing"*
([ADR-0013](0013-audience-is-a-family.md)).

**Spending is all-or-nothing.** `spend_charge()` returns false and changes
nothing below a full bar, so no caller can half-fire an ability.

## Consequences

- The dash is an **impulse through the existing knockback path**, not a
  teleport and not a speed buff. `Fighter`'s own wall push-out therefore stops
  it at stone with no new collision code, and the existing friction bleeds it
  off. A dash that crossed walls would be a hole in the arena.
- Caltrops drop **at the dropper**, not thrown ahead. A thrown one needs an aim,
  a flight and a landing preview, turning a panic button into a skill shot —
  wrong for the youngest player and wrong for the class, which drops these while
  backing out of a fight it is losing.
- Caltrops deal damage **per second**, not once on entry. Once-on-entry rewards
  dancing in and out of the patch, which is fiddly on a touchscreen and
  invisible to a child.
- Bots spend charge on the condition the ability is *for* — dash only with a
  target too far to shoot, caltrops only while retreating — and at low
  `bot_skill` they often simply forget, which reads as a bot that is bad at
  using an ability rather than one that is bad at aiming.
- Re-measured with abilities live, the class balance held: **48% and 52%**.
