# ADR-0027: Measure a debt before paying it — an adjective is not a number

**Status:** Accepted · M3.6

## Context

`docs/ARCHITECTURE.md §9` carried six known debts, each with a stated cost.
Nobody had ever measured one. When the branch to pay them opened, the first
thing it did was measure, and **four of the six rows turned out to be wrong
about their own cost — in both directions.**

The setting matters. Nobody on this project can run the game on a desktop, so
there is no profiler, no `adb logcat`, no frame graph. Every performance claim
in the codebase was therefore an argument from the shape of the code, and every
feel change across five consecutive PRs assumed a steady 60 fps that nobody had
checked.

## What the measurement said

`tools/measure_frame.gd` plays a real 3v3 headlessly and times every
`SimWorld.tick()`, splitting the samples by what the bots were doing.

| Debt row, as written | Measured |
|---|---|
| "`_nearest_cover()` … negligible on 24×14" | **478 µs a call**, against a 226 µs mean tick, called **every tick a bot is retreating** with no cache. Ticks with somebody retreating: 536 µs. Without: 226 µs |
| "`Tuning.get_value()` … dictionary lookup in hot paths" | 85.8 calls a tick at 0.34 µs = **29 µs, or 0.17% of a 60 Hz frame** |
| "`_free_bullet()` is a linear scan of 150 — O(n) per shot" | ~34 shots/s, ~75 field reads each. **Invisible** |
| "Web export is a debug build (36 MB wasm) — slow first load" | 10.1 MB *gzipped*, and the release export is **bigger**: 40.1 MB vs 38.5 MB, identical compressed |

One row understated its cost by two orders of magnitude. Three overstated
theirs, and one of those three proposed a fix that would have made the artifact
worse *and* deleted the on-device tuning panel, since it gates on
`OS.is_debug_build()`.

## Decision

**A debt is measured before it is paid, and closing one by measurement is a
result.** Three of the four rows above were closed without a line of code
changing, and the row that was real got fixed.

Three rules follow, and they are the part worth keeping:

**1. The denominator has to be the frame, not the tick.** The plan for this
branch set the bar for caching tuning lookups at "5% of tick time". Measured,
they are 9.3% of a tick — over the bar — and 0.17% of a frame. The tick is not
the budget; the frame is. A bar against the wrong denominator would have bought
four new places for a slider to silently stop working (ADR-0021) in exchange
for a sixth of one percent.

**2. A performance change must not change behaviour, and that is testable.**
The cover fix changes only the *order* cells are visited, which is sound
because the search keeps a running minimum — so any order returns the same
cell, and order decides only how early the distance test prunes. That argument
is backed two ways: an oracle test comparing the new search against the old
loop verbatim over 800 probes, and 24 seeded matches producing a **byte-
identical** score distribution to `main`. A perf PR whose distribution moves is
a gameplay change wearing a disguise.

**3. Try it, measure it, and revert it if it does not pay.** A Dictionary
open-set for `GridPath` was written, measured three runs each way — 382 µs
against 359 µs — and reverted, because Variant hashing costs more than a short
C++ linear scan. A parallel data structure that can desync, for no measured
gain, is a net negative. **The revert is the deliverable in that case**, and it
belongs in the commit message rather than being quietly dropped.

## What this cost, and what it bought

The branch shipped two permanent instruments, and they are worth more than the
optimisation:

- **`FrameStats`, in the DBG Info tab.** The HUD has always shown fps, and fps
  is the wrong number: a mean of 60 with a 40 ms spike reads as "60 fps" and
  feels like a trigger that does not respond. It now counts the frames that
  *missed* — over 20 ms, over 33 ms, the worst since reset and the worst in the
  last five seconds — with a Reset button, because the measurement that matters
  is "during a fight", not "since launch". `verify_ui.gd` asserts it is on
  screen, per ADR-0019.
- **`tools/measure_frame.gd`**, so the next person to claim something is slow
  has to bring a number.

**The honest limit, stated once:** headless has no renderer, so all of the
above measures the *simulation* only, on a container CPU several times faster
than a Tensor G4. It says the simulation is ~1.5% of a frame here and that one
function was distorting 30% of the frames in a match. It does not say the game
runs at 60 fps on the phone. Only the phone says that, which is exactly why the
readout shipped alongside the fix.

## Also recorded here

`test_tuning_keys.gd` scanned source for `Tuning.get_value("…")` and pinned
every key to the defaults file. It was green for four milestones while
`GAME_DESIGN.md` — this project's stated source of truth — described a bow that
no longer existed, down to a `draw_time_full` of 0.45 s and a magazine of ten.
Source is now not the only thing audited: a backticked snake_case name in a
*living* document must name something that exists in the codebase.

Comments are stripped from that corpus, which is load-bearing rather than tidy:
a comment is prose and goes stale exactly like a document does. The test's own
explanation names the dead keys it was written to catch, and with comments
counted that alone hid two of the three.

`docs/decisions/` is excluded. An ADR is a dated record, immutable by the rule
in its own README, and ADR-0016 naming `arrow_lifetime` is correct history
rather than rot.
