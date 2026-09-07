# ADR-0013: The audience is a family, not one adult

**Status:** Accepted · M3 · supersedes the audience premise in
[ADR-0006](0006-two-delivery-channels.md) and the single-player scope in the
original plan

## Context

For four milestones the stated audience was one person. `docs/GAME_DESIGN.md`
said so outright: *"The player is one person: the developer, on a Pixel 9. There
is no audience to balance for."*

That is now false. The real product is **a 3v3 game played over local WiFi with
a 5-year-old and a 10-year-old**, both of whom play Brawl Stars, in one room on
their own Android phones. It has to be competitive without being stressful or
punishing.

This does not extend the design. It **contradicts** parts of it.

## Decision

Four settled decisions are reversed, and one refusal is withdrawn.

### 1. Local multiplayer moves onto the critical path

Previously "the eventual ceiling, deferred not promised". It is now the point of
the project — without it there is no game — which is why M3.0 spiked the
transport before anything else was built on the assumption.

### 2. The snap shot no longer costs damage

`snap_damage_mult` was 0.5. Brawl Stars charges **nothing** for tap-to-auto-aim;
it is simply less flexible than aiming manually. Our version taxed the single
mechanic that makes the game playable for a 5-year-old.

The multiplier stays as a slider, so the trade can be reintroduced by turning a
dial rather than editing code. `test_bow.gd` was rewritten accordingly: it now
asserts the multiplier is *applied* and that a snap is never *stronger* than an
aimed shot — properties of the code — rather than asserting it is weaker, which
was a design decision wearing a test's clothes.

### 3. TTK lengthens

"Soldat's lethality, TTK 1.5–2.5s" was right for one adult. Brawl Stars is
deliberately ~3–6 hits, and that is the correct reference for a child. Raised by
increasing health rather than cutting damage, so the numbers on screen stay
chunky and the feedback stays satisfying.

### 4. Progression must never compound

Verified rather than assumed: Brawl Stars power levels are **persistent** and
grant **+10% health and damage per level, +100% at Level 11**. Brawl Stars
survives that because trophy matchmaking pairs similar accounts.

**Three fixed players in one room have no matchmaking.** The child who plays
more would acquire a permanent, unbridgeable statistical advantage over a
5-year-old — the exact opposite of "competitive but not punishing", and the
default outcome if levelling is copied from the reference game.

So: **levels reset every match** (1→5, XP from damage, kills and objectives,
with the losing team earning faster), and persistent unlocks are **cosmetic
only**. Kids get the level-up loop and the collecting loop with no power gap.

### 5. No per-player handicap system

Considered and **declined by the user**, knowing the risk. Recorded because the
alternative was recommended and refused, and that is worth not re-arguing.

The mitigations that exist anyway are not a handicap system: they apply to
everyone equally. Removing the auto-aim tax, the longer TTK, class asymmetry and
catch-up XP all narrow the gap without labelling anyone, and `aim_assist_deg` is
a live slider if a session goes badly.

## Consequences

**Good:** the game now has a real purpose and a real deadline — three people
around a table. Several mechanics get simpler, not more complex.

**Bad, and worth naming:**

- **Documentation written hours earlier is now wrong**, which is exactly the
  failure mode the docs rules were written to prevent. `GAME_DESIGN.md` and
  `ARCHITECTURE.md` are corrected in the same PRs that invalidate them.
- **The literacy constraint rules out the obvious UI.** "Pick one of three
  upgrade cards" and text-labelled classes are both out. Icons, colour and
  silhouette only, designed in rather than retrofitted.
- **LAN is the first feature this project cannot verify.** There is no second
  device in the build environment. A loopback test covers everything but the
  radio; the rest needs hardware and a person.
- **Balance is now a real problem** rather than a preference. Two children of
  different ages competing directly is a genuinely hard design target, and no
  amount of tuning fully solves a five-year age gap.

## Alternatives

| | Verdict |
|---|---|
| Keep the single-player design, add LAN later | Rejected — the reason to build this at all is playing it together |
| Copy Brawl Stars' persistent power levels | Rejected — verified at +100% at max, and there is no matchmaking to hide it |
| Persistent but capped (say +16% total) | Rejected as still compounding in the one direction that hurts; per-match levels give the same feeling with none of the drift |
| No levelling at all | Rejected — the growth loop is a thing these players specifically expect and enjoy |
| Per-player assist profiles | **Recommended and declined by the user.** Their call; recorded so it is not re-argued |
