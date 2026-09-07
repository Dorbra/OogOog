# M3.0 — LAN transport spike

**Status: shipped, awaiting a verdict from real hardware.**

This is an experiment, not a feature. It exists to answer four questions that
cannot be answered from a build machine, and the answers decide how M3.3 is
built.

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

## How to run it

Install the APK on two or more phones **on the same WiFi**.

1. On phone A: **DBG → Net → HOST**.
2. On phone B: **DBG → Net → FIND GAMES**, then tap the host in the list.
3. Move around. A **blue cat** is the other player.

If the list stays empty, type phone A's IP into the box and tap **JOIN**. That
distinction matters — see question 2.

## The four questions

### 1. Does ENet connect at all between these phones?

Watch `state` and `peers` in the Net tab. `JOINED` with `peers 1` is a yes.

A no here is fundamental and changes the plan: it would most likely mean the
network isolates clients from each other, and the fallback would be one device
acting as a hotspot rather than everyone joining the house WiFi.

### 2. Does broadcast discovery survive the router?

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

### 3. What is the actual latency?

The Net tab reports **worst ping** across peers, measured at the application
layer: request to reply including frame scheduling, which is the delay a player
feels rather than the delay the socket sees.

This is the number that decides M3.3's architecture:

| Worst ping | What it means |
|---|---|
| **under ~50 ms** | Host-authoritative with **no prediction and no rollback** is sufficient. An enormous simplification. |
| 50–120 ms | Playable, but the local player needs input prediction so their own cat responds instantly. |
| over ~120 ms | Something is wrong with the network rather than the code. Investigate before writing netcode around it. |

Loopback measures 6 ms. Real WiFi should land in the low tens.

### 4. Does the `InputCommand` seam hold?

Not answered by this spike, and deliberately so. Here **every peer publishes its
own position** — which is *not* the architecture the real game will use. M3.3
makes the host authoritative: clients send `InputCommand`, the host runs the one
true simulation, and broadcasts the result.

Separating the two keeps the questions separate. This one is about the network.
That one is about the simulation.

## What to report back

The Net tab has a **Copy net status** button. Paste the text. It carries the
role, peer ids, per-peer ping, whether discovery found anything, and the last
error — which is everything needed to tell the four questions apart.

## Files

| File | Role |
|---|---|
| `src/net/net_link.gd` | ENet host/join, peer tracking, position publishing, application-level ping |
| `src/net/lan_beacon.gd` | UDP broadcast discovery, so nobody types an IP |
| `src/debug/debug_overlay.gd` | The **Net** tab — the experiment's entire UI |
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
