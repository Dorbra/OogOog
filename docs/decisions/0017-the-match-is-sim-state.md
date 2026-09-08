# ADR-0017: The match is simulation state, and the freeze is a phase

**Status:** Accepted · M3.2

## Context

Bots landed in M3.1d and the game finally had a fight in it. It had no end:
no score, no clock, no start and no finish. `docs/GAME_DESIGN.md` said so
outright — cats simply fought until the app was closed.

Two questions had to be answered together, and the second is the one that is
usually got wrong: **where does "who is winning" live**, and **how does the game
stop moving during a countdown or a results screen**.

## Decision

### Score, clock and phase live in `src/sim/`, not in the HUD

`MatchState` is a plain `RefCounted` owned by `SimWorld`. No nodes, no engine
`Timer`, no `_process`.

The obvious alternative — a `Timer` on the HUD and a score the view keeps —
would put the entire win condition outside the headless test suite, which is the
only correctness signal this project has ([ADR-0003](0003-sim-view-split.md),
[ADR-0008](0008-no-physics-engine.md)). Whether a level score at the time cap
ends the match is exactly the kind of rule that is wrong once and then wrong
forever, and it is now asserted rather than played.

Kills needed attribution to be scored at all. `apply_damage()` gained
`attacker_team: int = -1`, and the default is load-bearing: unattributed damage
scores for nobody, which keeps every existing caller compiling and is the honest
answer for a future hazard.

### The freeze is a phase, not `get_tree().paused`

Outside `Phase.LIVE`, `SimWorld.tick()` returns before touching a fighter or an
arrow.

Pausing the scene tree is the reflexive answer and it is wrong here: it would
take the **tuning panel** down with it. Adjusting sliders between rounds is the
entire on-device workflow ([ADR-0004](0004-runtime-tuning.md)) — the moment you
most want to change a number is right after seeing how a match went. A phase
check also keeps the freeze inside the simulation, where a test can assert that
nothing moves during a countdown *and* that everything moves after it. "Nothing
moved" alone passes against a game that never simulates at all.

### A level score does not end the match

At the time cap the leader wins; level, play continues until someone leads by
one. Handing two children a draw is an anticlimax, and it costs one condition.

### The kill target was measured, not chosen

The plan said 15, written before `fix/pacing`. Twenty-four simulated two-minute
matches after it:

```
scores     : 1-0 x11, 2-0 x4, 0-0 x2, 3-0, 4-0, 5-0 x2, 5-1, 6-0, 7-0
decided by : kill target 0/24    clock 24/24    (6 reached sudden death)
```

15 would have been dead code, and so would the 10 agreed after it. **6** fires
on about an eighth of matches — a blowout backstop, which is what it is for.

## Consequences

**Good:**
- The whole win condition is headless-testable, and is: scoring, attribution,
  both end conditions, the tiebreak, single-emission, and that a match always
  ends rather than running forever.
- The tuning panel stays live between rounds, which is when it is most useful.
- `MatchState` is the natural place for M3.3 to make the host authoritative.

**Bad:**
- **`GameView` had to become re-buildable.** Its cat views are index-matched to
  `SimWorld.fighters`, so a new round at a different team size left it indexing a
  roster that no longer existed. Rebuilding is now explicit and the old views are
  detached immediately rather than via `queue_free()`, which is deferred.
- The headless smoke test now boots into the setup screen, where nothing
  simulates, so it covers less than it did. Live-simulation coverage moved to the
  render captures, which force `Phase.LIVE` — a real shift in which gate is
  carrying that weight, and worth knowing when reading a green run.
- **Sudden death has no clock of its own.** It leans on kills being frequent
  enough to break a tie, and kill rate is a slider. Pinned by a liveness test,
  because a match that never ends is indistinguishable from a hang on a phone.
