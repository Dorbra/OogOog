# Game design

What OogOog is trying to be, which mechanics serve that, and what has been
deliberately refused.

> This is a design document, not a wish list. Anything not built yet is marked
> **planned** with the milestone that owns it. Anything refused is in §9, so it
> can be refused again later with a reason rather than re-argued.

---

## 1. The pitch

**A 3v3 top-down cat shooter for phones, played over local WiFi.** Brawl
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

## 3. The gun is the whole control scheme

**Archers were tried first, and the theme was replaced rather than tuned.** The
reasoning for a bow was good and it is worth keeping visible, because it was
wrong in the hand rather than wrong on paper:

1. The gesture and the fiction were the same action — drag back, hold, release.
2. Draw strength collapsed recoil, spread and accuracy cones into one legible
   number.
3. An arrow is a line and a triangle, which is the most forgiving art there is.

What it actually produced was a **450 ms hold in front of every shot**, on a
projectile slow enough that a target drifted 1.14 cat-widths during its flight:

> *"the Arrow shooting is sluggish and cant be expected, lets change back to
> GUNS! with a clear line-of-fire"*

So the draw curve is **deleted, not turned down**
([ADR-0022](decisions/0022-guns-supersede-archers.md)).

### Tap to fire

- **Press** on the right half starts a gesture and fires **nothing**.
- **Release** fires one round immediately: in the drag direction if the drag
  passed `snap_max_drag`, auto-aimed and **leading** if it did not.
- Classified on **drag distance alone**. A hold threshold used to be half of it,
  so a player lining up a careful shot had it silently reclassified as an
  auto-aimed tap for taking too long.
- The rate limit lives in `Gun.consume()`, so the player and the bots are gated
  by the same code and a fast tapper has shots **refused rather than queued** —
  queueing would turn quick fingers back into lag.

### Auto-repeat

`auto_repeat` (default **off**): holding the right thumb keeps firing at the
gun's own rate. Tap-to-fire is what was asked for and is what ships; this stays
as a slider for when thumbs get tired, and it adds no timing of its own — the
cooldown in `Gun` remains the single source of fire rate.

---

## 4. Combat model

### Damage: every shot is the same shot

| | |
|---|---|
| Bullet speed | 1400 px/s |
| Reach (speed × lifetime) | 231 px — inside the 248 px half-view |
| Flight to maximum range | 165 ms |
| Damage | 28 (7.1 hits to a kill) |
| Deviation | none |
| Fire interval | 0.35 s, magazine 5, reload 1.1 s |
| Required lead | 6.1°, against a cat subtending 7.2° |

That last row is the design in one line: **point at a cat and the bullet arrives
where you pointed**, at every range. Nothing varies between one shot and the
next, which is a real loss — draw strength was the only shooting depth there was.
Class asymmetry in M3.4 is what replaces it, and until then the shooting is
deliberately plain.

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

### Movement: slow enough to read, slow enough to lead

| | |
|---|---|
| Speed | 150 px/s — **2.6 of a cat's own length per second** (Brawl Stars ≈ 2.4) |
| Crossing the visible height | 3.3 s (it was 2.0) |
| To full speed | 0.17 s, with ~14 px of coast on release |

**Measured in body-lengths per second, not pixels.** It is the one measure of
"how fast does this look" that survives a change of zoom, and it is what made the
complaint legible: the game shipped at **4.3** lengths per second and read as
*"the characters are fast and the movement is too sharp, there's no chance to aim
and hit like this"*.

There is a little weight in the acceleration, but not much. Brawl Stars is itself
snappy — what stops it feeling sharp is that it is slow *relative to the screen*,
not a long acceleration curve, and on a touch screen a real glide reads as
unresponsive rather than as momentum.

### Aiming: leading is the skill, and the game only nudges

| | |
|---|---|
| Arrow speed | 520 px/s at full draw, 0.44 s of life → **229 px** of reach |
| Lead a player owes | ~16° at any range |
| Unled shots still hit within | **65% of reach** — measured, not derived |

Point straight at a close cat and you connect; at the range bots hold station you
have to lead. That band is the answer to *"movement not too fast, but your aim
skill does matter"*, and it is set by `arrow_lifetime` far more than by arrow
speed — a longer flight is more drift to lead.

It is **measured by firing an arrow**, never computed. The obvious arithmetic —
compare the lead angle against the angle a cat subtends — said leading mattered
past 75% of reach; fired for real, an unled shot hit at 100% of it, because the
swept collision test scores the arrow's closest approach rather than where it
lands. `tools/measure_matches.gd` prints the real number for the current build.

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

### The match: two minutes, first to ten

| | |
|---|---|
| **Length** | 2 minutes. Short enough that a five-year-old stays in it start to finish, and that losing badly is over quickly |
| **Win** | First team to `match_target_kills` (10), or whoever leads when the clock runs out |
| **Level at the clock** | **Not a draw.** Play continues until one side leads by one |
| **Between rounds** | Results screen, then a tap. No auto-restart |

**The kill target is a measured number, not a chosen one, and it has moved
twice.** It was set to 6 because at the kill rate of the time a target of 10 or
15 decided 0 of 24 simulated matches — dead code rather than a mercy rule. The
movement and aiming fixes in
[ADR-0020](decisions/0020-aim-assist-must-predict.md) roughly tripled the kill
rate, at which point 6 decided 15 of 24 and the clock had stopped mattering. At
**10** the clock decides 20 of 24 and the target fires only on a blowout, which
is what it is for and what was asked for. Recorded in
[ADR-0017](decisions/0017-the-match-is-sim-state.md); re-measure it with
`tools/measure_matches.gd` after any change that alters how often anyone meets
anyone.

**Nothing on any of these screens is written down.** A five-year-old cannot read
"3v3" or "BLUE WINS", so team size is a row of cats you tap, the countdown is a
numeral, and the result is one team standing and one sitting with two
colour-coded scores. No per-player statistics, ever: publishing who died most,
every round, to the youngest player is the opposite of *competitive but not
punishing*.

### Magazine: 5 rounds, one back every 1.1 s

Lifted from Brawl Stars' ammo rhythm. It is not a resource to manage across a
match — it is a **pacing device**. It gates spam and forces the "am I committed
to this fight?" decision, which matters *more* once regen exists, because
disengaging is always an option.

### Bots: they stop moving, on purpose

A bot used to apply a lateral strafe term on **every tick it could see anybody**,
reversing every 1.2 s, so it never once stood still. Six of those read as frantic
darting at any movement speed — and the report was about the enemies, not the
player, whose speed was already inside its own gate.

Strafing is now a duty cycle: **60 % moving, 40 % standing**, with a deadband so
a bot that has reached its preferred range actually stops there rather than
creeping across it forever
([ADR-0023](decisions/0023-bots-must-stand-still.md)).

Measured over 24 seeded matches, this did something that was not the goal:
**shutouts fell from five to one**. A bot that pauses is readable to the other
bots as well as to you, so fights resolve on position rather than on whoever
happened to be circling the right way.

### Health: regenerate out of combat

`regen_delay` 4.5 s, then `regen_rate_pct` 20 %/s → zero to full in about 10 s of
not being shot. The delay is the lever that matters, not the rate: you cannot
heal above maximum, so a slower rate only delays topping up.

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
| **Aim assist strong enough to aim for you** | `aim_assist_deg` is **4°** and, since [ADR-0020](decisions/0020-aim-assist-must-predict.md), it bounds how far the game may bend your shot rather than merely admitting it. A 4° gate that then snapped onto the intercept would be a lock-on: the lead a player owes is about 16°, so the game would be doing all of the aiming. It defaulted to 0 while the audience was one adult; [ADR-0013](decisions/0013-audience-is-a-family.md) changed that premise. It stays a slider. |

---

## 10. Open design questions

Things that are genuinely undecided, and what would settle them.

- **Does regen produce stalemates?** Both players trade, disengage, heal to full,
  repeat, and the match never resolves. Counters are already in the design —
  magazine limits, damage-charged abilities, a match timer — but this needs real
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
