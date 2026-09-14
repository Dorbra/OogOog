# ADR-0032 — the network is the fourth producer of an `InputCommand`

**Status:** accepted (M4.2, `feat/lan`)

## Context

Three people in one room, each on their own phone, is what this project is for.
[ADR-0013](0013-audience-is-a-family.md) moved local multiplayer from "the
eventual ceiling" onto the critical path, and every milestone since has been
building the game it is meant to carry.

The question was how much of the simulation has to change to put it on a wire.

## Decision

**None of it.** `SimWorld.tick()` is byte-for-byte what it was before this
branch.

[ADR-0003](0003-sim-view-split.md) drew one seam — the simulation reads only an
`InputCommand`, never `Input`, never a node — and `src/sim/input_command.gd`
predicted this exact payoff in M1, in its own header:

> *"if same-WiFi multiplayer ever happens, the network becomes a third producer
> and the simulation does not change at all."*

It is the fourth, counting the empty command a fighter with no controller gets,
and it did not change. `SimWorld.tick()` already reads

```gdscript
var f_cmd := cmd
if f != player:
    f_cmd = _command_for(f, delta)   # -> f.controller.think(f, self, delta)
```

so a person on another phone is a `Fighter` whose `controller` is a
**`RemoteController`** that hands back the last command received. That is the
whole integration. The same was true of bots in M3.1d, which makes this the
second time the seam has absorbed a feature that would otherwise have been a
rewrite, and the reason to keep paying for it.

`RemoteController` lives in `src/ai/` beside `bot_controller.gd`, not in
`src/net/`. Putting it under the network layer would say the simulation knows a
socket exists, which is the one thing the seam is for. Nothing in it imports
anything networked: commands are pushed in from outside.

## Host-authoritative, no prediction, no rollback

One device runs `SimWorld` and everybody else draws what it says.

```
host    runs SimWorld.tick(),         broadcasts Snapshot.capture()
client  runs SimWorld.tick_replica(), sends its InputCommand
```

**A client is not prevented from deciding things. It never runs the code that
decides them.** There is no `if is_client` inside `tick()` that somebody can get
wrong in a later refactor — there are two functions, and a client calls the
other one. `tick_replica()` cannot fire a gun, apply damage, score a kill or
kill anybody, because it contains none of those calls.
`test_a_client_never_decides_anything` asserts that as an outcome: a second of
replica ticks with every fighter charged, loaded and standing on top of each
other produces no shots, no damage and no score.

That design is only viable because LAN latency is small. It was **assumed rather
than measured**, deliberately, to avoid a separate spike PR ahead of a working
game — and the assumption is made falsifiable instead of hidden: the DBG Net tab
reports the worst ping with its own verdict against 50 ms. If it reads badly the
fix is client-side prediction on movement only, which is a change to
`net_game.gd` and nothing else.

## The replica runs at 60 Hz, and that is what keeps the view untouched

Snapshots arrive at 30 Hz. The view interpolates with
`Engine.get_physics_interpolation_fraction()` between `prev_position` and
`position`, so applying packets straight into `position` would have meant
teaching `game_view.gd`, `fx.gd`, `camera_rig.gd` and `cat_view.gd` about the
network.

Instead a snapshot writes `Fighter.net_target`, and `tick_replica()` eases
`position` toward it **once per physics tick**. The pair the view reads keeps
meaning what it always meant. Not one view file learned anything.

(One view file did change: `game_view.gd` **lost** `_sync_remote_views`, the
spike's peer-position cats. That is a deletion of scaffolding the file's own
comment said would go — *"M3.3 makes the host authoritative and remote players
become ordinary fighters, at which point this goes away"* — not the view
learning about replication.)

## Three rules that are tests rather than intentions

**A stale peer goes quiet.** A phone that locks its screen, walks out of range
or drops a run of packets stops sending. Repeating its last command would leave
its cat sprinting into a wall and firing forever — and still scoring. Past
`net_stale_ticks`, `RemoteController` hands back an empty command. Asserted in
both directions, because "it goes quiet eventually" alone passes on a controller
that never worked.

**One release is one bullet.** `fire`, `snap` and `ability` are edges. Read
twice — which they are, at 30 Hz packets against a 60 Hz simulation — one
release becomes two bullets, and a remote player quietly shoots at double the
rate of the person hosting. The edge is consumed at the tick boundary, which is
the same contract `TouchControls.take_fire()` gives the local player, in the
same place.

**A payload this build cannot read changes nothing at all.** Two phones updated
minutes apart is the normal case here — the APK is installed by hand on three
devices — so a version mismatch will happen. Applying the prefix of a payload we
half understand would put three cats at new positions and three at old ones,
which reads as lag rather than as a mismatch and would be debugged for an hour.
`Snapshot.apply()` refuses whole, on the version or on a length that disagrees
with its own header.

## The feedback layer is derived, not transmitted

`Fx` and `CameraRig` subscribe to `hit` and `killed`, which only
`apply_damage()` emits — and a client never calls it. Without something, two
players out of three would get no damage numbers, no hitstop, no shake and no
particles: the exact *"nothing responds when you hit it"* the whole M1.3 juice
pass existed to fix.

So `Snapshot.apply()` derives them from the health delta. The **damage is
exact** — it is the difference between two numbers that were sent. The
**direction is an approximation**, and is named as one in the code rather than
pretended about: it drives a particle spray and a shake vector, neither of which
any player can check, and putting an event stream on the wire to improve them
would cost traffic for nothing anybody can see.

## Consequences

- The simulation gained two functions and no branches.
- A client's seat has to be told to it: `world.player` is what the camera
  follows, what the ammo pips and charge ring are drawn from, and what decides
  an event is yours. On a joined device that is not `fighters[0]`, and the host
  sends the seat **with the team size**, because a client whose roster is a
  different size rejects every snapshot on the length check — correctly, with a
  frozen arena over a healthy connection as the symptom.
- The loopback gate grew from "a `Vector2` crossed" to the whole round trip:
  every controller on the host is nulled except the client's seat, so a bullet
  existing at all is proof the command crossed, was acted on by the authority,
  and came back.
- **The host owns the tuning.** See [ADR-0033](0033-the-host-owns-the-tuning.md).
