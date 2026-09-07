# ADR-0007: Typed sim events, not polling

**Status:** Accepted · M1.3

## Context

Before the juice pass, the view polled sim state every frame — `main.gd` looped
over dummies looking at `hit_flash`.

Polling can express **"is hurt"**. It cannot express **"was just hit, from that
direction, for this much damage, on a full draw"**. Every piece of combat
feedback needs the second one. That polling model, not the effects themselves,
was the actual blocker for the entire feel milestone.

## Decision

**`SimWorld` emits typed signals at the moment things happen, and all damage
funnels through one method.**

```gdscript
signal hit(position, direction, damage, full_draw)
signal killed(position, direction)
signal fired(position, direction, draw_strength)
signal arrow_expired(position)
```

`SimWorld.apply_damage()` is **the single entry point for every point of damage
in the game**. That is what guarantees the view cannot miss a hit: there is no
second path that damages something quietly.

Subscribers: `Fx` (particles, numbers, rings, hitstop) and `CameraRig` (shake).

## Consequences

**Good:**
- Effects get exact data at the exact moment — direction for the particle burst,
  damage for the number, `full_draw` for the reward colour.
- **Adding a subscriber requires no sim change.** Sound in M4 hangs off exactly
  these signals; nothing needs rewriting for it.
- The events are unit-testable: a hit emits **exactly once** with the right
  damage; a kill emits once and not again while dead.

**Bad:**
- The sim now knows it is observed. It does not know *by whom*, which keeps the
  dependency direction correct, but signals are still a form of coupling.
- **`died_this_tick` is a latch**, set on death and cleared once observed. It is
  a small piece of state that exists purely so the kill event fires once — easy
  to break, and pinned by a test.
- Signal handlers written as lambdas hit GDScript's capture-by-value trap. This
  broke two tests and the screenshot tool's capture trigger.

## Alternatives

| | Verdict |
|---|---|
| Keep polling | Rejected — cannot express the moment or direction of a hit |
| An event queue drained by the view | Rejected — more machinery than signals for identical behaviour at this scale |
| The view reaching into sim internals | Rejected — breaks [ADR-0003](0003-sim-view-split.md) and makes the sim untestable |
