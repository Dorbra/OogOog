# ADR-0019: A capture proves it drew; only an input proves it works

**Status:** Accepted · M3.2b

## Context

> *"Actually the game is stuck on first initial screen and I cant get past it.
> Clicking doesn't do anything 😕"*

The setup screen could not be dismissed. Not "was awkward" — **the game was
unplayable from the first frame**, and it shipped that way.

The cause is one line. `MatchScreens` is a `Control` parented to a `CanvasLayer`,
and its `_ready()` said:

```gdscript
set_anchors_preset(Control.PRESET_FULL_RECT)
```

A `Control` under a `CanvasLayer` has **no Control parent for anchors to resolve
against**, so that leaves it at `size = (0, 0)`. A zero-size Control can never be
hit, so `_gui_input()` never fired, and no tap did anything at all — ever.

### Why every gate stayed green

| Gate | Why it saw nothing wrong |
|---|---|
| Unit tests (369 assertions) | They build no scene tree. There is no Control to have a size. |
| Headless smoke test | Boots the scene and reports errors. A zero-size Control is not an error. |
| **Render captures — all four** | **They drew the screen perfectly.** |

That last row is the important one. `_draw()` is **not clipped by a Control's
rect**, and every layout in `MatchScreens` is computed from
`get_viewport_rect()`. So the picker rendered exactly right — the cats, the
rings, the play triangle — at a size of zero. The screenshots I looked at, and
described as correct, were correct. They were also completely uninformative
about whether the thing worked.

## Decision

**Add a gate that delivers real input to the real scene**, and treat capture and
interaction as answering different questions.

`tools/verify_ui.gd` (via `tools/verify_ui.sh`, in CI) instantiates
`scenes/main.tscn`, then:

- asserts every interactive Control has a **non-zero rect covering the viewport**
  and does not have `MOUSE_FILTER_IGNORE`;
- **taps each cat in the size picker** and asserts the right side size is chosen;
- **taps the play button** and asserts a match starts;
- **taps the results screen** and asserts the next round begins — because a
  finished round that cannot be dismissed traps the player exactly as the setup
  screen did.

It runs under `xvfb`, like the render test, and for a sharper reason: **headless
gives a square 1280×1280 viewport and does not route GUI input at all**, so a tap
delivered there proves nothing while appearing to pass.

Ten checks. Restoring the shipped line fails seven of them.

## Consequences

**Good:**
- The class of bug is closed, not just the instance. Any future screen that draws
  but cannot be touched fails CI.
- The results screen is covered too — it had the same latent trap and nobody had
  reached it to find out.

**Bad:**
- It needs a display, so it is slower than a unit test and shares xvfb's
  flakiness surface with the render test.
- It reaches into `_slot_rect()` and `_play_rect()`, which are private. Tapping
  hard-coded coordinates instead would break the moment the layout moved, which
  is worse — but it is coupling, and it should be named.

## The general lesson

[ADR-0012](0012-verify-inside-the-artifact.md) says verify the artifact rather
than the process. This is the sharper version:

**Verify the artifact doing its job, not the artifact existing.**

A screenshot is evidence of drawing. It is not evidence of working, and I read it
as though it were — described the picker as correct, shipped it, and it had never
once been touchable. The same reasoning already caught a `.txt` file missing from
an export and a combat capture firing into a wall. This is the third time the
answer has been "inspect the thing actually doing what it is for", and the second
time in this milestone that a **test itself** had to be broken on purpose before
it could be trusted.
