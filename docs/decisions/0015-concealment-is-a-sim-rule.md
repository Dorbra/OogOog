# ADR-0015: Concealment is a simulation rule, not a fade

**Status:** Accepted · M3.1d

## Context

`Arena.conceals()` shipped in M2 with the bushes, and until now it had **exactly
one caller**: a line in `game_view.gd` that faded the player to 55% alpha while
standing in one.

So bushes hid nothing. Every fighter was fully targetable and fully visible from
anywhere on the map, and the "best mechanic in the reference game" was a
cosmetic effect. This did not matter while nothing fought back. It became the
blocker the moment bots were asked to use cover: an ambush is not expressible
when everyone can see into every bush.

## Decision

**One rule, in the simulation, that both the AI and the view read:**

```gdscript
SimWorld.can_see(from: Vector2, target: Fighter) -> bool
```

```
target.reveal_timer > 0     -> visible   # shooting gives you away
within reveal_radius        -> visible   # you can see into a bush you are next to
arena.conceals(target.pos)  -> hidden
otherwise                   -> line of sight, via Arena.cast_segment()
```

The view asks the simulation rather than reading `Arena.conceals()` itself. A
cat the AI had lost track of but that the player could still see — or the
reverse — would make cover unreadable, and that is exactly what two independent
implementations drift into.

Three consequences that are decisions in their own right:

- **A hidden enemy is not drawn at all**, and neither is its health bar. A
  floating green bar over an empty bush gives away precisely what the bush is
  hiding.
- **Teammates in cover stay visible**, faded. Losing track of your own side is
  not a mechanic, it is confusing, and for a 5-year-old that outweighs the
  symmetry.
- **`nearest_visible_enemy()` is a second function, not a change to
  `nearest_enemy()`.** The plain distance query is what `tools/screenshot.gd`
  stages against and what `test_fighters.gd` asserts non-null; team spawns sit
  across the map behind stone, so filtering it in place would have broken a test
  for reasons unrelated to what it tests.

Switching the snap-shot lock and `_apply_aim_assist()` to the visible variant is
a **bug fix riding along**: both previously locked onto targets through solid
walls. That is the same broken promise `autoaim_radius` was cut from 900 to 700
to avoid in M3.1c — auto-aiming at something the bow cannot reach, or cannot
reach *through*.

## Consequences

**Good:**
- Ambush exists. `Arena.conceals()` finally does something.
- Auto-aim stops selecting targets behind walls.
- One definition of "visible", so the screen and the AI cannot disagree.

**Bad:**
- **This changes how the game plays for a person, not just for a bot.** Enemies
  now vanish. That is the intent, and it is also the most likely thing to feel
  wrong on the phone — `reveal_time` and `reveal_radius` are sliders for exactly
  that reason.
- `can_see()` casts a ray per candidate. Six fighters makes it negligible; it is
  not free.
- A concealed enemy is invisible to the *local* player only. When M3.3 makes the
  host authoritative, this rule has to be evaluated per viewer.
