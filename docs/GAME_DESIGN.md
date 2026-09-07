# Game design

What OogOog is trying to be, which mechanics serve that, and what has been
deliberately refused.

> This is a design document, not a wish list. Anything not built yet is marked
> **planned** with the milestone that owns it. Anything refused is in §9, so it
> can be refused again later with a reason rather than re-argued.

---

## 1. The pitch

**A top-down archer brawler for phones.** Soldat's lethality inside Brawl Stars'
structure: short matches, twin-thumb controls, travelling projectiles, health
that regenerates out of combat.

Two references, each contributing something specific:

| From Soldat | From Brawl Stars |
|---|---|
| Projectiles that *travel* and can be dodged | Short matches with a clear end |
| Fights resolve in seconds, not attrition | Twin-thumb touch controls that actually work |
| Positioning and cover decide fights | Out-of-combat regen instead of health pickups |
| | Ammo as a rhythm, not a resource to hoard |
| | Bushes: cover that breaks line of sight, not movement |

**The player is one person: the developer, on a Pixel 9.** There is no audience
to balance for and no retention metric to serve. The design target is "fun in the
hand for ten minutes", nothing more.

---

## 2. Design pillars

Three, in priority order. When two conflict, the higher one wins.

### I. It must read on a 6" screen in daylight

Every mechanic has to be legible at a glance, mid-fight, on a small bright
screen. This is why:

- Arrows are the warmest, brightest thing on screen (`#ffd166`) against
  mid-to-dark green grass.
- **Walls are stone, bushes are foliage.** They behave completely differently —
  one stops arrows, one only breaks sight — and must be distinguishable without a
  legend.
- Draw strength is *one* number instead of a recoil/spread/accuracy-cone stack.
- Damage numbers are outlined, and full-draw hits get a distinct colour.

### II. Commitment must be rewarded, and the fast option must stay viable

The central tension. A full draw is slow, precise and hurts; a snap shot is
instant, weak and *aims itself*. Neither dominates, so the player is making a
real decision several times a second rather than executing one optimal input.

### III. The feedback loop is part of the design

Not a development detail — a *design constraint*. Nobody involved can run this
game on a desktop. Every feel parameter is therefore a runtime slider, and "what
number should this be" is answered with thumbs on a phone instead of argument in
a pull request. A mechanic that cannot be tuned on-device is a mechanic that
cannot be balanced ([ADR-0004](decisions/0004-runtime-tuning.md)).

---

## 3. The bow is the whole control scheme

**Why archers, not guns.** This is the load-bearing theme decision and it earns
its place three separate times:

1. **The gesture and the fiction are the same action.** Drag back, hold, release.
   For a bow that is literal. For a rifle, drag-then-release is arbitrary and has
   to be learned.
2. **Draw strength collapses a whole stack of shooter mechanics into one
   legible number.** Hold longer → faster arrow, more damage, less deviation.
   That is recoil, spread and accuracy cones replaced by one thing the player can
   *see* in the reticle.
3. **It is the most forgiving art to produce.** An arrow is a line and a
   triangle. It survives placeholder quality far better than guns and muzzle
   flashes — which matters when there is no artist.

### The gesture

```
Left thumb   floating joystick, appears where it lands
Right thumb  drag = DIRECTION     hold = POWER     release = LOOSE
```

Direction and power are independent axes of one gesture, so both are expressed
without a mode switch.

### Snap shot: auto-aim attached to the weak option

Release with almost no drag and almost no hold → an instant shot, auto-aimed at
the nearest target within `autoaim_radius`, for `snap_damage_mult` (0.5×) damage.

**This is the most important single design decision in the control scheme.**
Auto-aim is *mandatory* on a phone — precise manual aim on a 6" screen does not
work, and pretending otherwise is how touch shooters become unplayable. But
auto-aiming everything removes all skill expression.

Attaching auto-aim to the fast, weak shot and withholding it from the slow,
strong one resolves both: aiming is never *required*, but aiming is always
*worth it*.

### Auto-repeat

`auto_repeat` (default on): holding keeps firing each time the draw completes.
The quiver and its refill become the rate limiter instead of the player's thumb.

This exists because of a real playtest complaint — "less 1 shot 1 pull, slow
pull". Without it every shot costs a full press-hold-release gesture, which reads
as sluggish however fast the draw itself is. It is a **slider, not a rewrite**,
so the other model stays available.

---

## 4. Combat model

### Damage: draw strength drives everything

| | Min draw | Full draw |
|---|---|---|
| Arrow speed | 700 px/s | 1450 px/s |
| Damage | 14 | 42 |
| Max deviation | 8° | 0° |

Full draw takes `draw_time_full` = 0.28 s. A full-draw hit is 3× a rushed one and
flies dead straight, which is the entire argument for committing.

### Quiver: 3 arrows, one back every 0.85 s

Lifted from Brawl Stars' ammo rhythm. It is not a resource to manage across a
match — it is a **pacing device**. It gates spam and forces the "am I committed
to this fight?" decision, which matters *more* once regen exists, because
disengaging is always an option.

### Health: regenerate out of combat

`regen_delay` 3 s, then `regen_rate_pct` 20 %/s → zero to full in about 8 s of
not being shot.

**Why regen instead of health pickups:** pickups make map control the dominant
strategy and punish the losing player twice. Regen means a fight that goes badly
costs you *tempo* rather than the rest of the match. It is the Brawl Stars / CoD
model and it suits short sessions.

The gate is **time-since-damage**, not an "in combat" boolean. Boolean flags
always end up with one code path that forgets to clear them.

### Cover: two kinds, and they must never look alike

| | Blocks movement | Blocks arrows | Blocks sight |
|---|---|---|---|
| **Wall** `#` | yes | yes | yes |
| **Bush** `b` | no | no | yes |

Bushes are the single best mechanic Brawl Stars has, and they create ambush play
out of almost no code. `Arena.conceals()` already ships; the bot AI is its first
real consumer.

An open field makes top-down shooting into pure aim practice. Cover is what turns
it into positioning.

---

## 5. Feel — the juice layer

Feedback is designed, not decoration. The gap between "a prototype" and "a game"
on first touch is almost entirely here.

| Effect | What it communicates | Key |
|---|---|---|
| Hitstop | Impact weight | `hitstop_hit` 32 ms @ 0.15 scale |
| Screenshake (trauma²) | Severity, accumulating | `shake_hit` / `shake_kill` |
| Damage numbers | Exact reward, full-draw in a distinct colour | `number_size` |
| Knockback | Arrows carry mass | `knockback_force` 260 |
| Trajectory reticle | Where the shot will land, growing with draw | `reticle_enabled` |
| Arrow trails | Fast arrows stay readable | `trail_length` |
| Squash & stretch | Loose, flinch, death | `squash_amount` |
| Chip health bars | A big hit reads as big | — |

**Every magnitude is a slider**, because these are the easiest things in game
development to overdo. Hitstop was already dialled back once after a playtest:
45 ms at 0.08 scale put roughly a third of a firefight in slow motion, which
reads as *lag*, not impact.

> **Stated honestly:** juice amplifies whatever is underneath it. Underneath is
> currently target practice. This makes the game feel far better to *touch*; it
> does not yet make it something to play for ten minutes. The fight does that.

---

## 6. Art direction

**Cats, in a sunny garden.**

Cats are drawn **upright and camera-facing, flipping left/right** rather than
rotating top-down. From directly overhead a cat is an oval with two ear
triangles, which throws away the entire point of choosing cats. Flip uses
hysteresis so a cat aiming near-vertical does not strobe.

Because the cat no longer rotates, **aim needs its own carrier**: a procedurally
drawn bow — an arc plus a string — orbits the cat at its aim angle. It shows
direction precisely *and* makes "this is an archer" legible, which a coloured
circle never did.

Two SVG layers, not one file per colour: `cat_body.svg` is a pure-white
silhouette tinted via `modulate`, `cat_face.svg` carries untinted details on top.
Any number of cat colours from two hand-written files. Both stick to simple paths
and flat fills, because Godot rasterises SVG through ThorVG, which supports a
subset and has no filter support.

**A soft ellipse shadow under every cat.** Cheap, and the single biggest thing
that stops top-down sprites looking like stickers floating on the background.

Terrain is procedural — noise ground, seeded scatter, pond, path — because there
is no image editor in this workflow.

> **The ceiling, stated once:** hand-authored SVG plus procedural terrain gets
> from "programmer shapes" to "deliberate, readable, stylised". It does not get
> to shippable character art. That remains a real artist or money, and naming it
> now avoids pretending otherwise later.

---

## 7. Where it is now

| Milestone | State |
|---|---|
| M0 pipeline | done |
| M1 controls + tuning panel | done |
| M1.1 landscape, camera, faster firing | done |
| M1.2 cats and garden | done |
| M1.3 juice | done |
| M2 arena cover | done |
| **M3 bots + match loop** | **next** |
| M4 content — 3 archers, abilities, pickups, sound | planned |
| M5 polish — profiling, thermals, release build | planned |

**The honest summary: nothing fights back yet.** Everything above is a
well-built shooting gallery. `feat/bots` is the milestone that makes it a game.

---

## 8. Planned, in order

1. **`feat/bots`** — finish the `Actor`/`Dummy` unification `Health` started.
   FSM: seek → strafe at preferred range → retreat. Aim by leading the target
   **plus a deliberate error term**, and that error term is the difficulty knob.
   Bots use the same draw mechanic as the player, or they feel like they cheat.
2. **`feat/match-loop`** — player health, death, respawn, deathmatch to N kills,
   countdown, results screen.
3. **`chore/tech-debt`** — see [ARCHITECTURE.md §9](ARCHITECTURE.md#9-known-debt-stated-honestly).
4. **`feat/super`** — an ability charged by **damage dealt, not a cooldown**.
   With regen covering survival, this is what pulls players toward fights instead
   of away from them.

### Planned characters (M4)

Differentiated by **weapon behaviour, not stat sliders** — three bows that play
differently, rather than one bow with three damage numbers.

| | Weapon | Ability |
|---|---|---|
| Ranger | Baseline. Full draw-reward, medium range, flat | Dash / roll |
| Skirmisher | Rapid short bow, 3-arrow fan, short range | Caltrops |
| Longbow | Slow arcing lob that flies **over walls**, AoE on landing | Burning zone |

---

## 9. Deliberately refused

Recorded so they can be declined again with a reason.

| Refused | Why |
|---|---|
| **Progression, currency, shops, unlocks, accounts** | Single-player, one user. Every hour spent here is an hour not spent on the fight. |
| **Online / dedicated-server multiplayer** | Costs money and ops forever. Same-WiFi LAN is the ceiling, and it is deferred, not promised. |
| **Hitscan weapons** | Travel time is what makes shots dodgeable and readable, and what keeps LAN plausible. |
| **A physics engine for collision** | [ADR-0008](decisions/0008-no-physics-engine.md) — headless testability is worth more than engine features here. |
| **Making the pond gameplay-relevant** | It is decorative. Water that slows or damages is a real design decision deserving its own change, not something smuggled into a cover PR. |
| **2D lights** | Expensive on mobile for a flat-shaded game that gains nothing from them. |
| **Aim assist on drawn shots by default** | `aim_assist_deg` exists and defaults to **0**. Bending a shot the player aimed themselves erodes the entire commitment trade. It is a slider so difficulty can be dialled in on the device rather than argued about here. |

---

## 10. Open design questions

Things that are genuinely undecided, and what would settle them.

- **Does regen produce stalemates?** Both players trade, disengage, heal to full,
  repeat, and the match never resolves. Counters are already in the design —
  quiver limits, damage-charged abilities, a match timer — but this needs real
  bots to test. **Settled by:** playtesting after `feat/bots`; the regen delay
  and rate are the first dials to turn.
- **Is `auto_repeat` on or off by default?** Currently on. **Settled by:** thumbs.
- **Does the arena read well?** Cover density, corridor widths, spawn placement
  are one text-file edit away. **Settled by:** playing it and saying what is
  wrong, rather than guessing at numbers.
- **How hard should bots be?** The aim error term is the knob. **Settled by:**
  tuning it on the device — which is exactly what the tuning panel exists for.
