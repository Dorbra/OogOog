# ADR-0006: Two delivery channels

**Status:** Accepted · M0 · *publishing mechanism partly superseded by
[ADR-0011](0011-pages-from-a-branch.md)*

## Context

The APK loop is download + install: ~6 minutes and a handful of taps. That is
acceptable as a checkpoint and unacceptable as an iteration loop.

## Decision

**Two channels, used for different questions.**

| | Channel A — web | Channel B — APK |
|---|---|---|
| Loop | ~3 min, refresh | ~6 min, download + install |
| Answers | Movement, aim, layout, balance | Performance, thermals, real touch latency |

**The web export is single-threaded**, deliberately. GitHub Pages cannot set the
COOP/COEP headers that `SharedArrayBuffer` requires, and mobile Safari and
Firefox Android do not support the threaded path anyway. A single-threaded build
runs everywhere with no special headers.

**Never judge performance on Channel A.** The web build's timing does not
represent the device. Stated in the README, in `CONTRIBUTING.md`, and in the
sticky comment on every PR, because it is exactly the kind of thing that gets
forgotten right when it matters.

## Consequences

**Good:** most iteration happens on a 3-minute loop, and the APK stays the
authority for anything performance-shaped.

**Bad:**
- **Two artifacts to keep honest.** A bug present in only one channel is
  confusing, and the "which build am I looking at" question is real enough that
  the commit hash is rendered in the HUD.
- **Web lies about performance.** There is a standing risk of tuning something
  that feels fine in Chrome and stutters natively. Mitigated only by discipline:
  checkpoint on the APK at every milestone.
- The single-threaded debug wasm is 36 MB — a slow first load on mobile data.

## Alternatives

| | Verdict |
|---|---|
| APK only | Rejected — a 6-minute loop cannot tune feel |
| Web only | Rejected — cannot answer performance, thermals or true touch latency |
| Threaded web build | Rejected — Pages cannot set the required headers |
