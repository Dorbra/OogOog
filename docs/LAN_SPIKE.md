# M3.0 — LAN transport spike

**Status: CLOSED by `feat/lan` (M4.2). Three of its four questions are now
answered by the code; the fourth still needs two phones on a real router, and
the build that can answer it finally exists.**

> **The correction that closed it, kept because the trap recurs.** From M3.0 to
> M4.1 this document told people to run the spike from a **Net tab** in the DBG
> overlay. There was no Net tab. `debug_overlay.gd` built Tuning, Log and Info
> and nothing else; `NetLink` and `LanBeacon` were reachable only from
> `tools/net_probe.gd`, the loopback gate, and `main.gd` never touched either.
>
> So the four questions below sat "awaiting a verdict from real hardware" for
> **five milestones with no build in which they could be answered.** The
> instructions were written for a UI the PR did not ship — exactly the failure
> [ADR-0019](decisions/0019-appearance-is-not-behaviour.md) and
> [ADR-0027](decisions/0027-measure-a-debt-before-paying-it.md) are about: a
> document asserting a capability the artifact does not have.
>
> It was recorded rather than quietly fixed so `feat/lan` would start from what
> was true. **The Net tab is built now**, and so is the thing it was supposed to
> be testing.

## What to actually do now

The spike's own peer-to-peer position model is **gone** — deleted, not disabled.
`feat/lan` built the real thing on top of the transport
([ADR-0032](decisions/0032-the-network-is-a-command-producer.md)), so there is
nothing left to run separately:

1. Install the same APK on two or more phones on the same WiFi.
2. On phone A, tap the **cat with a plus** on the first screen.
3. On phone B, tap the **cat with a magnifier**, then tap the game it finds.
4. Phone B picks a class; phone A picks the team size and presses play.
5. **Then open DBG → Net on both and read the ping**, during a real fight
   rather than in the lobby, five seconds after joining — ENet seeds round-trip
   time at 500 ms and converges.

If the list on phone B stays empty, go to **DBG → Net**, type phone A's IP into
the box and tap **Join**. That distinction still matters — see question 2.

---

It existed to answer four questions that cannot be answered from a build
machine. Their answers were supposed to decide how the real netcode was built;
in the end three of them were answered by building it, and the remaining one is
the only thing between here and three people playing in one room.

---

## Why a spike at all

Local multiplayer is not a nice-to-have on this project any more — it *is* the
product. The game is meant to be played by three people in one room on their own
phones. If ENet does not work across that particular router, every milestone
after this one is aimed at the wrong target.

That is worth a day to find out, rather than two milestones.

## What it cannot tell us here

**There is no second device in the build environment.** This is the first thing
in the project that the automated gates genuinely cannot verify. What they *can*
verify is everything upstream of the radio, and `tests/test_net_loopback.sh`
does: two headless Godot processes over 127.0.0.1, server creation, client
connection, peer signals, RPC delivery, and state actually crossing both ways.

That catches the ordinary breakages — a renamed API, a wrong `@rpc` annotation,
a peer never polled. It leaves exactly one class of question for hardware.

## How it was meant to be run

*(Superseded — see "What to actually do now" at the top. Kept because the
question numbering below refers to it.)*

1. On phone A: **DBG → Net → HOST**.
2. On phone B: **DBG → Net → FIND GAMES**, then tap the host in the list.
3. Move around. A **blue cat** is the other player.

## The four questions

### 1. Does ENet connect at all between these phones? — **still open**

Watch the role and `peers` in the Net tab. `CLIENT` with one peer is a yes.

A no here is fundamental and changes the plan: it would most likely mean the
network isolates clients from each other, and the fallback would be one device
acting as a hotspot rather than everyone joining the house WiFi.

### 2. Does broadcast discovery survive the router? — **still open**

Many consumer access points drop broadcast traffic between wireless clients —
"AP isolation", and most guest networks. When that happens **ENet still connects
fine by direct address, but the game list stays empty.**

This is why the manual IP box exists, and why the two paths are reported
separately. "Found nothing" and "found it but could not connect" are different
problems with different fixes, and a single "it didn't work" would hide which
one occurred.

If discovery fails but manual joining works, M3.3 needs a different join flow —
probably a short room code — because *"ask an adult for the IP address"* is not
a viable way for a 5-year-old to join a game.

### 3. What is the actual latency? — **THE ONE THAT MATTERS**

The Net tab reports **worst ping** across peers, measured at the application
layer: request to reply including frame scheduling, which is the delay a player
feels rather than the delay the socket sees.

`feat/lan` did not wait for this number. It **assumed** the first row and built
host-authoritative with no prediction and no rollback — a deliberate choice, to
avoid a whole spike PR ahead of a working game, and one the user made knowing
the risk. The Net tab exists so the assumption is falsifiable in ten seconds
instead of leaving "it feels laggy" as the only evidence:

| Worst ping | What it means |
|---|---|
| **under ~50 ms** | Host-authoritative with **no prediction and no rollback** is sufficient. An enormous simplification. |
| 50–120 ms | Playable, but the local player needs input prediction so their own cat responds instantly. |
| over ~120 ms | Something is wrong with the network rather than the code. Investigate before writing netcode around it. |

Loopback measures 6-7 ms. Real WiFi should land in the low tens, and the tab
prints its own verdict against 50 ms so the reading needs no interpretation.

**If it reads badly, the fix is known and contained**: client-side prediction on
movement only, in `src/net/net_game.gd`, against a game that already works.

### 4. Does the `InputCommand` seam hold? — **ANSWERED: yes, completely**

This was the question the spike deferred, and building the real thing answered
it better than any experiment would have. **`SimWorld.tick()` is byte-for-byte
unchanged by `feat/lan`.** A person on another phone is a `Fighter` whose
`controller` is a `RemoteController`, which is the same shape a bot has had
since M3.1d.

`src/sim/input_command.gd` called this in M1 — *"the network becomes a third
producer and the simulation does not change at all"* — and it was exactly right.
Recorded in [ADR-0032](decisions/0032-the-network-is-a-command-producer.md).

The spike's own model is deleted: every peer publishing its own position was
never the architecture, `NetLink` said so at the time, and leaving it in would
have meant a dead RPC transmitting `(0, 0)` to every peer twenty times a second
for a whole match.

## What to report back

The Net tab has a **Copy net status** button. Paste the text. It carries the
role, peer ids, per-peer ping, whether discovery found anything, and the last
error — which is everything needed to tell the four questions apart.

## Files

| File | Role |
|---|---|
| `src/net/net_link.gd` | ENet host/join, peer tracking, position publishing, application-level ping |
| `src/net/lan_beacon.gd` | UDP broadcast discovery, so nobody types an IP |
| `src/debug/debug_overlay.gd` | The **Net** tab — the experiment's entire UI. **Not built.** The three fields it needed (`_net_label`, `_host_list`, `_address_edit`) were declared and never assigned, and were deleted in M4.1 rather than left looking like a feature |
| `tools/net_probe.gd` | Headless host/client probe |
| `tests/test_net_loopback.sh` | Two processes, 127.0.0.1, state both ways. Runs in CI |

## Two bugs this found before it reached a phone

Worth recording, because both would have been near-undiagnosable on a device:

- **`multiplayer` is null during a SceneTree script's `_initialize()`.** The node
  is in the tree but the MultiplayerAPI is not live yet, and the engine reports
  it as "assignment on a null instance" rather than anything actionable. Every
  access now goes through a checked accessor that names the problem.
- **Calling `rpc()` while a client is still CONNECTING** logs an error on every
  attempt. Harmless in itself, but it would have buried the real diagnostics in
  the log panel that is the only way to read anything on a phone.
