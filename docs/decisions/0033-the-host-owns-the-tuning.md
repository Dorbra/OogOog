# ADR-0033 — the host owns the tuning

**Status:** accepted (M4.2, `feat/lan`)

## Context

[ADR-0004](0004-runtime-tuning.md) is the decision the whole project's workflow
rests on. There is no PC: the feedback loop is commit → CI → download → install
→ play, about ten minutes, and tuning how a game feels needs fifty small
adjustments. Every feel constant is therefore a live slider on the device, and
the loop that actually works is *drag it, feel it, copy the JSON, paste it back*.

That decision has always assumed **one device**. `feat/lan` makes that false for
the first time.

## Decision

**On a client, the DBG sliders stop changing the fight.**

Not by being disabled — by being irrelevant. The host runs `SimWorld`; the
client runs `tick_replica()` and draws what arrives. `move_speed`,
`bullet_damage`, `fire_interval`, `regen_delay` and every other key that decides
an outcome are read by the code running on the host. A client dragging
`move_speed` changes a number nothing on that device reads.

So: **tune on the host.** That is the whole rule, and it needs saying out loud
because the alternative is rediscovering it as a bug — three people in a room,
one of them dragging a slider and reporting that it does nothing.

## Why not send the tuning

Considered and refused. Sending 76 keys 30 times a second to say they have not
changed would be the largest thing on the wire by an order of magnitude, for a
feature used seconds at a time by one adult.

Sending them **on change** was the tempting middle. It was refused too, for a
reason that outlives the traffic argument: it would make a client's panel look
like it worked, while the keys it could actually move were an undocumented
subset of the keys it displays. A slider that silently does nothing is exactly
the failure [ADR-0021](0021-a-tuning-override-must-be-visible.md) was written
about — a shipped default quietly overridden with nothing on screen to say so —
and this would be the same shape with the roles reversed.

**A rule that is always true beats a mechanism that is usually true.** The host
decides; everybody else is looking at a picture.

## What a client's panel still does

Genuinely, and worth keeping straight:

- **The Log tab** reads that device's own `user://logs/godot.log`. When the
  five-year-old's phone is the one misbehaving, that is the only way to find out
  why, and it has to be on the phone it happened on.
- **The Info tab** reports that device's frame times. A client that stutters and
  a host that stutters are different problems.
- **The Net tab** reports that device's ping and role — which is the point of it.
- Anything purely local to drawing still applies on that device only.

## Consequences

- The on-device tuning workflow survives LAN intact, on one device instead of
  three, which is how it was always actually used.
- `Snapshot` carries no tuning keys, and its header comment says why.
- A client's `user://tuning.json` overrides still apply to that device's view
  and to any solo game it plays afterwards. The override badge from ADR-0021
  still tells the truth about that.
- If per-player feel ever becomes wanted — and
  [ADR-0013](0013-audience-is-a-family.md) refused per-player *handicaps*, not
  per-player *comfort* — it is a deliberate feature with a roster entry, not a
  slider that happens to work.
