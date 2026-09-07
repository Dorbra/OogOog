# ADR-0008: Pure-maths collision, no physics engine

**Status:** Accepted · M2

## Context

Godot ships a 2D physics engine. Using it for arrows and walls is the obvious
move: `Area2D` for projectiles, `StaticBody2D` for walls, collision layers, done.

But physics bodies are **nodes**, and nodes need a scene tree, which needs a
running engine. That would put collision — the most correctness-critical part of
combat — outside the headless test suite, in a project where headless tests are
the only correctness signal that exists ([ADR-0003](0003-sim-view-split.md)).

## Decision

**All collision is pure maths on plain objects.** No `Area2D`, no
`PhysicsBody2D`, no collision layers.

| Interaction | Algorithm | Why this one |
|---|---|---|
| Arrow vs. target | **Swept circle** | At full draw an arrow covers ~24 px per tick against a 42 px radius. Endpoint testing lets fast shots tunnel |
| Arrow vs. wall | **DDA grid traversal** (Amanatides & Woo) | Exact, ~25 lines. Sampling along the segment would reintroduce tunnelling in a second place |
| Actor vs. wall | **Circle push-out, iterated twice** | One pass leaves a circle wedged in a concave corner still overlapping the other wall |

Order matters and is a correctness property: **walls resolve before targets**,
with the arrow's segment truncated to the impact point first. Reverse it and a
target behind a wall gets hit through it.

## Consequences

**Good:**
- Collision is fully unit-tested headless — tunnelling, corner resolution, first
  wall along a path, spawn points landing on open cells.
- No physics tick, no layer configuration, no engine-version behaviour changes.
- Deterministic within a platform, and trivial to reason about.

**Bad:**
- **Hand-written geometry has hand-written bugs.** Two were found by tests, and
  one of those was a bug in the *test*:
  - Escaping a wall by the nearest face ejects out of a **border** cell into
    off-grid space, which is itself treated as solid. Push-out now prefers the
    nearest face whose neighbour is actually open.
  - The first version of that test asserted a corner cell could be escaped. It
    cannot — all four neighbours are walls, so no correct answer exists.
- Broad-phase is naive: every active arrow tests every living dummy. Fine at
  dozens; would need a grid at hundreds.
- Anything physics-shaped later — bouncing, sliding, joints — is hand-written or
  a rewrite.

## Alternatives

| | Verdict |
|---|---|
| `Area2D` + `StaticBody2D` | Rejected — moves collision out of headless tests |
| A third-party 2D physics library | Rejected — dependency weight for problems this project does not have |
| Tile-aligned movement | Rejected — would change the game into something grid-based |
