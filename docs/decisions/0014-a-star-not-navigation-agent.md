# ADR-0014: Bots are an InputCommand producer, and navigate by A* over the grid

**Status:** Accepted · M3.1d

## Context

Nothing fought back. Five of the six cats in a 3v3 stood still, because
`SimWorld._command_for()` hands an empty `InputCommand` to any fighter with no
controller — which was all of them.

Two questions had to be answered to change that, and they are usually
answered together and badly: *what is a bot allowed to touch*, and *how does it
find its way around a wall*.

## Decision

### A bot is a third producer of `InputCommand`, with no other privileges

`BotController.think(me, world, delta) -> InputCommand`. That is the entire
surface. A bot cannot read `Input`, set a position, or reach past `Bow` to spawn
an arrow — it fills in the same six fields a thumb fills in and hands them back.

This required **no change to `Fighter`, to `SimWorld.tick()`, or to the view**.
The seam was already there from [ADR-0003](0003-sim-view-split.md), in one
branch, waiting:

```gdscript
var f_cmd := cmd
if f != player:
    f_cmd = _command_for(f, delta)
```

The consequence worth stating plainly: **bots cannot cheat by construction**.
They draw the bow at `draw_time_full` like everyone else, they run out of
arrows, and they wait for the quiver. When a bot out-shoots you it aimed better.

A corollary discovered while building it: a controller must **not hold a
reference to its target**. `Fighter.controller` keeps the bot alive, so a bot
holding a `Fighter` closes a cycle, and `RefCounted` cannot collect a cycle. The
target is passed down as an argument; only an instance *id* is stored, and only
to notice that the target changed.

### Navigation is A* over the arena's existing cell grid

Not `NavigationRegion2D` / `NavigationAgent2D`.

| | Verdict |
|---|---|
| **A\* over the grid** | **Chosen.** The grid already exists, an arena is a few hundred cells, and the search is pure maths on plain objects |
| `NavigationAgent2D` | Rejected — nodes, a baked resource, and collision moves back out of the headless tests |
| Steering / flow fields | Rejected — more machinery than a 24×14 arena can justify |

Same reasoning as [ADR-0008](0008-no-physics-engine.md): the headless test suite
is the only correctness signal this project has, and navigation belongs inside
it. `tests/test_grid_path.gd` asserts routes around walls, sealed pockets
terminating, and corner cuts refused — none of which is expressible against a
baked navmesh without an editor.

**One rule in that search is load-bearing rather than cosmetic:** a diagonal is
only legal when both orthogonal neighbours are open. `fighter_radius` is 29
against a half-cell of 30, so a path that squeezes between two walls is one the
collision push-out rejects on every tick — the bot would walk confidently into a
corner and vibrate there. It is pinned by a test that fails when the rule is
removed.

### Difficulty is one slider, and it gates cover play

`bot_skill` (0…1) is the single master. Aim error, reaction delay, target
leading and whether the bot ambushes at all are all derived from it.

At full skill a bot keeps **15% of its aim error and 20% of its reaction delay**
rather than dropping to zero. A bot that never misses and answers instantly is
not "hard", it is unpleasant, and it is the most likely way this feature ships
badly.

The gate on ambushes (`bot_cover_skill_gate`) is the deliberate reconciliation
of two things the user asked for that pull against each other — full cover play,
and one global difficulty for a 5-year-old and a 10-year-old in the same match
([ADR-0013](0013-audience-is-a-family.md)). Being killed from a bush you never
saw is the least fair thing in this design. It arrives with the skill.

## Consequences

**Good:**
- The AI is entirely headless-testable; `tests/test_bots.gd` drives `think()`
  directly and asserts on the command.
- One difficulty number to turn on the device mid-session, which is the only
  lever that matters when a match is going badly.
- The same seam takes a remote player in M3.3 with no further change.

**Bad:**
- The FSM was quick; **making bots fun will take longer than writing them did**,
  and that is a tuning problem no test can answer.
- A* allocates arrays per repath. Fine at 0.4 s intervals for five bots; it is
  not the per-frame churn [ADR-0009](0009-pool-combat-objects.md) is about.
- `_nearest_cover()` scans the whole grid casting a ray per open cell. Cheap on
  a 24×14 arena and the first thing to revisit if arenas grow.
