# ADR-0018: Feedback is for what happens to *you*

**Status:** Accepted · M3.2b

## Context

The second playtest of the 3v3 build:

> *"the screen doesn't stop shaking (STOP THAT SHIT!) ... it should feel much
> slower and steadier, just like Brawlstars!"*

`SimWorld` emits `hit`, `killed` and `fired` for **every fighter, anywhere on the
map** — which is right, because the simulation has no opinion about who is
looking. Three subscribers in the view then acted on every one of them with no
filter at all:

| Subscriber | What it did on every event | What that produced |
|---|---|---|
| `CameraRig.listen_to` | `add_trauma()` on hit, kill **and every shot fired** | Trauma arrived at ~0.72/s against a decay of 1.9/s and settled at a **permanent jitter that never reached zero**, punctuated by hard shakes from kills happening off screen |
| `Fx._on_hit` / `_on_killed` | `hitstop()`, which dips **`Engine.time_scale` globally** | The whole game micro-froze about **once a second** because two bots traded shots where the player could not see them |
| `Fx` particles, rings, numbers | Spawned at the event position | Pool slots burned on effects nobody could see |

With six fighters, **five of every six events belonged to somebody else,
somewhere else.** The player was being shown feedback for a fight they were not
in and could not see, which reads as the game malfunctioning rather than as
feedback.

None of this was visible in a screenshot, and no test asserted it.

## Decision

**Screen feedback answers "what just happened to me", not "what just happened".**

- **Camera trauma and hitstop fire only when the local player is the one hit or
  killed.** Both compare the event's position — already carried by every signal —
  against the player's, so no signal needed a new field.
- **`shake_fire` defaults to 0.** Your own bowstring moving the camera is not
  something the reference game does, and at five arrows a second it was the
  single largest contributor to the jitter.
- **Particles, rings and damage numbers are culled to the camera rect.** They are
  still position-based, because seeing a teammate's fight across the arena is
  fine; what is not fine is spending pool slots on one nobody can see.
- The remaining shake is dialled well down: `shake_hit` 0.32 → 0.18, `shake_kill`
  0.65 → 0.30, `shake_max_offset` 26 → 14, `shake_decay` 1.9 → 3.0.

### And the camera was framed too tightly to begin with

You could see **3.8 character-heights** vertically; the reference game shows
about eight. `camera_zoom` 1.8 → **1.45** puts a cat at 84 px (11.7% of screen
height, versus 14.5%) and **8.6 of them fit vertically**. The half-view — which
[ADR-0016](0016-range-is-bounded-by-the-camera.md) makes the budget for
everything that reaches — goes from 200 px to 248 px, which is what gave the bow
and the bots room without anything leaving the screen.

## Consequences

**Good:**
- The camera is still unless something happens to you, which is what "steady"
  meant.
- `tests/test_feedback.gd` asserts trauma returns to **exactly zero** across
  thirty seconds of a fight the player is not in, and that no hitstop is
  triggered by it — with the mirrors, so neither can pass against feedback that
  has simply been deleted.
- Fewer wasted pool slots and no time-scale churn from off-screen events.

**Bad:**
- "Concerns the player" is a **distance test**, not an identity test: a teammate
  killed while standing on top of you will shake the camera. That is arguably
  correct, and it is cheaper than growing every signal a victim field, but it is
  a heuristic and should be named as one.
- `Fx` now holds a reference to `SimWorld` to find the player. Still one-way —
  the view may read the simulation, never write it — but it is a new edge in the
  dependency graph.

## The part worth remembering

Two of the three tests written for this ADR **passed when the bug was
reintroduced**, and were only caught by negative-testing them:

- The hitstop test watched `Engine.time_scale`, which is applied in `_process()`
  — and `_process()` never runs for a node built outside the scene tree. It had
  to assert on `hitstop_left()` instead.
- The bot range test staged its target beyond *sight* range as well as beyond
  reach, so the bot never acquired anything and "did not fire" was true for the
  wrong reason.

[ADR-0012](0012-verify-inside-the-artifact.md) says verify the artifact rather
than the process. **A test is an artifact too**, and the only way to know one
works is to break the code and watch it go red.
