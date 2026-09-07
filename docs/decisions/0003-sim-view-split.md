# ADR-0003: Split simulation from view

**Status:** Accepted · M1

## Context

The correctness problem this project has is unusual: **nobody can run the game.**
No editor, no local play, no debugger. If the only way to find out whether combat
works is to install an APK, then combat logic is effectively untested.

Godot's default idiom pulls the other way — nodes that read `Input`, hold state,
and draw themselves. That is convenient and completely untestable headless.

## Decision

**The simulation never reads `Input` and never touches a sprite.**

```
producers ──InputCommand──▶ sim ──typed events──▶ view
```

- `src/sim/` runs in `_physics_process` at a fixed 60 Hz. Pure objects
  (`RefCounted`), no nodes.
- `src/view/` reads sim state to interpolate and subscribes to sim events.
- `InputCommand` is the only channel in. Thumbs produce one today; bot AI will
  produce one next; a network would be a third.

## Consequences

**Good:**
- **185 assertions run headless in under a second.** This is the only correctness
  signal the project has, and it exists solely because of this split.
- Bots cannot cheat by construction — they get an `InputCommand`, not state.
- LAN multiplayer stays possible without a rewrite. *Possible, not promised.*
- The `main.gd` god object was decomposable when it hit 237 lines, because the
  seams were already there.

**Bad:**
- More indirection than a Godot tutorial. Adding a mechanic means touching a sim
  type, an event, and a view subscriber.
- State is duplicated for rendering — every renderable carries `prev_position`
  purely so the view can interpolate.
- The discipline is convention, not enforcement. Nothing mechanically stops
  someone importing `Input` into `src/sim/`; only review does.

**Explicitly not attempted: determinism.** Cross-platform float determinism is a
rabbit hole and is unnecessary — LAN would be client-server authoritative, not
lockstep. Fixed timestep is for *stable gameplay*, not for replay equality.

## Alternatives

| | Verdict |
|---|---|
| Idiomatic Godot nodes | Rejected — untestable headless, which is fatal here specifically |
| Full ECS | Rejected — real benefits at thousands of entities; this has dozens |
| Deterministic lockstep sim | Rejected — enormous cost for a benefit no chosen feature needs |
