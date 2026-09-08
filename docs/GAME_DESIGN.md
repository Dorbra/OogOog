# Game design

What OogOog is trying to be, which mechanics serve that, and what has been
deliberately refused.

> This is a design document, not a wish list. Anything not built yet is marked
> **planned** with the milestone that owns it. Anything refused is in §9, so it
> can be refused again later with a reason rather than re-argued.

---

## 1. The pitch

**A 3v3 top-down archer brawler for phones, played over local WiFi.** Brawl
Stars' structure — short matches, twin-thumb controls, travelling projectiles,
health that regenerates out of combat — with cats.

It used to say "Soldat's lethality" here. That was right for one adult and is
wrong now: see the audience below.

Two references, each contributing something specific:

| From Soldat | From Brawl Stars |
|---|---|
| Projectiles that *travel* and can be dodged | Short matches with a clear end |
| Fights resolve in seconds, not attrition | Twin-thumb touch controls that actually work |
| Positioning and cover decide fights | Out-of-combat regen instead of health pickups |
| | Ammo as a rhythm, not a resource to hoard |
| | Bushes: cover that breaks line of sight, not movement |

**The players are a 40-something DevOps engineer and two children, aged 5 and
10, who love Brawl Stars.** They play together in one room, each on their own
Android phone, over the home WiFi.

That is the single most important fact in this document, and it changed the
design after the first four milestones were already built:

- **Local multiplayer is the product**, not an eventual ceiling.
- **TTK lengthens** toward Brawl Stars' ~3–6 hits. A 5-year-old who dies in two
  hits without understanding why stops playing.
- **Auto-aim stops being a tax.** The snap shot used to deal half damage;
  Brawl Stars charges nothing for tap-to-auto-aim, and taxing it punished the
  one mechanic that makes the game playable for the youngest player.
- **Progression must not compound.** See [ADR-0013](decisions/0013-audience-is-a-family.md).
- **A 5-year-old cannot read.** Class select, level-ups, HUD and results have to
  work in icons, colour and silhouette.

There is deliberately **no per-player handicap system** — the user's call, made
knowing the risk. The changes above narrow the gap without singling anyone out,
and `aim_assist_deg` is a live slider if a session is going badly.

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
the nearest target within `autoaim_radius`. It costs **no damage** — see the
audience section; `snap_damage_mult` remains a slider so the trade can be
re-introduced by turning a dial rather than editing code.

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
| Arrow speed | 480 px/s | 780 px/s |
| Reach (speed × lifetime) | 139 px | 226 px |
| Damage | 10 | 28 |
| Max deviation | 8° | 0° |

Full draw takes `draw_time_full` = 0.45 s. A full-draw hit is nearly 3× a rushed
one and flies dead straight, which is the entire argument for committing.

**Reach is not a free parameter.** 226 px sits inside the 248 px shortest
half-axis of what the camera shows, and
[ADR-0016](decisions/0016-range-is-bounded-by-the-camera.md) holds it there: if
something can hit you, you can see it. **So does bot sight range** — that bound
was missing at first, and bots shot from off screen for a whole milestone
because the test used a proxy instead of the screen. The first 3v3 playtest
was *"the bots just shot at me from out-of-screen"*, and measurement agreed —
79% of the enemies in range to hit the player were off screen. It is now 0%, and
a test fails if that changes.

**Time to kill: 200 hp ÷ 28 = about 7 full-draw hits**, up from 3.3. With three
enemies able to focus one player, 3.3 hits was the "dead in a second" the same
playtest reported.

### The camera: steady, and framed like the reference game

| | |
|---|---|
| Zoom | 1.45 — you see 883 × 497 of the world |
| A cat on screen | 84 px, 11.7% of screen height |
| Characters visible vertically | **8.6** (it was 3.8) |

**The camera does not move unless something happens to you.** Shake and hitstop
fire only when the local player is hit or killed, never for the other five
fighters' fights — [ADR-0018](decisions/0018-feedback-is-about-you.md). Firing
your own bow shakes nothing at all. This was a real defect, not a taste
preference: the screen previously never stopped jittering and the whole game
micro-froze about once a second for events happening off screen.

### Healing: why a fight resolves at all

Out-of-combat regen is the reason this game is not punishing, and it was also the
reason nothing ever died. Measured over two minutes of a real 3v3:

| | |
|---|---|
| Damage dealt | 2738 — enough to fund **13.7 kills** |
| Kills | **1** |
| Healing restored | **3301 hp — 121% of all damage dealt** |

**Lowering the heal RATE does nothing**, and that is worth writing down because it
is the obvious move. You cannot heal above maximum, so total healing is capped by
damage taken; a slower rate only delays topping up, and a two-minute match has
plenty of slow. Halving it moved the mean from 1.3 kills to 1.5.

The levers are **how often anyone gets an uninterrupted window to start healing**
(`regen_delay` 3 → **4.5 s**) and **how readily bots break off to take one**
(`bot_retreat_health` 0.30 → **0.12**). Chosen by sweeping both:

| delay | retreat | mean kills | player deaths standing still |
|---|---|---|---|
| 3.0 | 0.30 | 1.12 | 0 |
| 3.0 | 0.12 | 2.62 | 0 |
| **4.5** | **0.12** | **3.38** | **0** |
| 6.0 | 0.12 | 2.12 | 0 |

**More delay is not better** — 6.0 measures worse than 4.5. And retreat is the
bigger lever: at the original delay, changing it alone more than doubles kills.

Pinned by `test_matches_actually_resolve`, with a floor well under the measured
mean so ordinary tuning does not trip it and "matches stopped resolving" does.

### The match: two minutes, first to six

| | |
|---|---|
| **Length** | 2 minutes. Short enough that a five-year-old stays in it start to finish, and that losing badly is over quickly |
| **Win** | First team to `match_target_kills` (6), or whoever leads when the clock runs out |
| **Level at the clock** | **Not a draw.** Play continues until one side leads by one |
| **Between rounds** | Results screen, then a tap. No auto-restart |

**Six is a measured number, not a chosen one.** Across 24 simulated matches the
target decided 0 of them at 15 and 0 at 10 — it would have been dead code. At 6
it fires on about an eighth, which is the blowout backstop it is meant to be.
Recorded in [ADR-0017](decisions/0017-the-match-is-sim-state.md).

**Nothing on any of these screens is written down.** A five-year-old cannot read
"3v3" or "BLUE WINS", so team size is a row of cats you tap, the countdown is a
numeral, and the result is one team standing and one sitting with two
colour-coded scores. No per-player statistics, ever: publishing who died most,
every round, to the youngest player is the opposite of *competitive but not
punishing*.

### Quiver: 5 arrows, one back every 1.1 s

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
out of almost no code.

**Concealment is a simulation rule, not a fade**
([ADR-0015](decisions/0015-concealment-is-a-sim-rule.md)). Until M3.1d
`Arena.conceals()` had one caller — a 55% alpha on the player — so bushes hid
nothing from anyone. Now:

- **An enemy standing in a bush is not drawn at all**, and neither is its health
  bar. Bots cannot target it either; both read the same `SimWorld.can_see()`.
- **Shooting gives you away** for `reveal_time`. An ambusher who fires is
  visible whether or not it is still in cover — otherwise cover is not cover,
  it is invulnerability.
- **Standing within `reveal_radius`** reveals what is in there. You can walk a
  bush to check it, at the obvious risk.
- **Teammates in cover stay visible**, faded. Losing your own side is not a
  mechanic; for a 5-year-old it is just confusing.

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
| M3.1 fighters, teams, **bots** | done |
| M3.1e pacing — nothing shoots from off-screen | done |
| **M3.2 match loop — timer, score, results** | done |
| **M3.3 LAN — the actual product goal** | **next** |
| M4 content — 3 archers, abilities, pickups, sound | planned |
| M5 polish — profiling, thermals, release build | planned |

**Something fights back, and now a match ends.** Two minutes, first to six kills
or whoever leads on the clock, then a results screen and a tap for the next
round. Team size is picked from a row of cat icons before the whistle.

**The honest summary is now different again: everyone is playing alone.** The
whole point of this game is three people in one room, and until `feat/lan` lands
the other five cats are bots. That is the last milestone between here and the
thing the project is actually for.

---

## 8. Planned, in order

1. **`feat/lan`** — host, join, discovery. The three of you playing together,
   which is the entire point. Blocked on nothing but work: the M3.0 spike proved
   the transport on loopback at 7 ms, and the four questions it raised still need
   two real phones on a real router to answer.
2. **`feat/match-loop`** *(done — kept here for the ordering below)* — player health, death, respawn, deathmatch to N kills,
   countdown, results screen.
2. **`chore/tech-debt`** — see [ARCHITECTURE.md §9](ARCHITECTURE.md#9-known-debt-stated-honestly).
3. **`feat/super`** — an ability charged by **damage dealt, not a cooldown**.
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
| **Aim assist strong enough to aim for you** | `aim_assist_deg` is **8°** since M3.1c — enough to forgive a thumb, not enough to find a target you were not already pointing at. It defaulted to 0 while the audience was one adult who wanted to commit to a draw; [ADR-0013](decisions/0013-audience-is-a-family.md) changed that premise. It stays a slider. |

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
- **How hard should bots be?** ~~The aim error term is the knob.~~ **Answered
  in M3.1d:** one master slider, `bot_skill`, from which aim error, reaction
  delay, target leading and whether a bot ambushes at all are derived
  ([ADR-0014](decisions/0014-a-star-not-navigation-agent.md)). At full skill a
  bot keeps 15% of its error and 20% of its delay rather than becoming perfect.
  What is still open is **where to leave the slider for two kids five years
  apart**, and that is settled by playing, not by argument.
- **Do vanishing enemies read as fair, or as cheap?** Concealment became real in
  M3.1d and it is the biggest change to how a match feels. **Settled by:** the
  phone — `reveal_time` and `reveal_radius` are the first dials to turn, and
  `bot_cover_skill_gate` turns ambushes off entirely.
