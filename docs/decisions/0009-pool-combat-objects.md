# ADR-0009: Pool everything spawned in combat

**Status:** Accepted · M1 (arrows), M1.3 (effects)

## Context

Combat spawns objects continuously: arrows every ~0.3 s with auto-repeat, plus
particles, damage numbers and impact rings on every hit.

GDScript allocation churn shows up as **frame hitches** — and it does so exactly
during a firefight, which is the moment the game can least afford it and the
moment all the juice exists to smooth over.

## Decision

**Anything spawned during combat comes from a fixed-size pool allocated once at
startup.**

| Pool | Size |
|---|---|
| Arrows | 150 |
| Particles | 220 |
| Damage numbers | 40 |
| Impact rings | 24 |

Exhausting a pool **drops the effect**. It never allocates mid-combat and never
grows.

## Consequences

**Good:** no allocation in the hot path; hard, predictable memory ceiling; and
pooling was designed in from day one rather than retrofitted, which is tedious
and error-prone.

**Bad:**
- **Pool exhaustion is silent.** A dropped particle is invisible; a dropped
  *arrow* would be a gameplay bug. Caps are sized well above observed peaks, but
  nothing warns if one is hit.
- Pooled objects must be fully reset on reuse. A field left stale from the
  previous occupant is a genuinely nasty bug class.
- **`_free()` returning `{}` on exhaustion is a trap.** `if x == null` is always
  false for a `Dictionary`, so effects were being written into a throwaway object
  instead of dropped. Callers must use `is_empty()`.
- `SimWorld._free_arrow()` is a **linear scan of 150** on every shot. Correct but
  O(n); a free list is on the tech-debt list.

## Alternatives

| | Verdict |
|---|---|
| Allocate per spawn | Rejected — this is the documented cause of GDScript frame hitches |
| Godot `GPUParticles2D` | Rejected — less control over batching, and the effects need exact per-hit data from sim events |
| Growable pools | Rejected — turns a predictable ceiling into an unpredictable hitch under load |
