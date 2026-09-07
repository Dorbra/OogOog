# ADR-0005: Text-first authoring

**Status:** Accepted · M0

## Context

Godot's authoring model assumes an editor: scenes are built by dragging nodes,
tilemaps by painting cells. There is no editor here, and content still has to be
created and — crucially — **reviewed in a GitHub diff on a phone**.

## Decision

**Everything authored is a text format a human can type and read in a diff.**

- **Arenas are ASCII grids** parsed at runtime, not `.tscn` tilemap data:
  ```
  #  wall    b  bush    P  spawn    .  open
  ```
- **Scenes are built in code.** There is exactly one `.tscn` and it contains one
  node. `.tscn` is technically a text format, but every hand-written scene is a
  chance to break something invisible until CI runs.
- **Data is JSON** — tuning, the arena legend, the build stamp.
- **Characters are hand-written SVG** — simple paths and flat fills, because
  Godot rasterises through ThorVG, which supports a subset and has no filters.

## Consequences

**Good:**
- A layout change is a diff anyone can read. `#` moving one column is obvious in
  a way that a binary tilemap edit never is.
- The arena file became the **source of truth for world size** — bounds derive
  from `cols × cell_size`, which deleted a `WORLD_SIZE` constant that `SimWorld`,
  `Terrain` and `CameraRig` each had to agree on by hand.
- Content is diffable, greppable and mergeable.

**Bad:**
- **No visual authoring.** Designing a map in a text editor is genuinely worse
  than painting one, and it will not scale to twenty arenas.
- Parsing and validation are code that must be written and tested — 260 lines in
  `arena.gd`, 208 in its tests.
- The parser must be forgiving, because the format is hand-edited on a phone.
  Ragged rows and unknown characters are treated as open ground rather than
  errors: failing a build over a short line would make the format hostile.
- **A text file is not a Godot resource.** This directly caused the arena being
  dropped from every export — see [ADR-0012](0012-verify-inside-the-artifact.md).

## Alternatives

| | Verdict |
|---|---|
| `TileMapLayer` + `.tscn` | Rejected — needs the editor; unreadable in a diff |
| A custom binary format | Rejected — all the downsides, none of the diffability |
| Generate arenas procedurally | Rejected for now — hand-placed cover is a design decision, and a generator is a project of its own |
