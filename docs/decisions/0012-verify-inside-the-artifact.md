# ADR-0012: Verify the artifact, not the process

**Status:** Accepted

## Context

`data/arenas/arena_01.txt` was never inside a single exported build. Not the web
build, not the APK, for two merged pull requests.

`export_filter="all_resources"` with an empty `include_filter`, and Godot counts
only what it can *import* as a resource. `.json` qualifies. `.svg` qualifies.
**`.txt` does not.**

Every symptom followed from that one file: an empty grid → a zero-size world →
the ground texture drawn into an empty rect (a grey screen), no walls, no spawn
points, and the player falling back to the origin.

**The damning part is why nothing caught it.** The unit tests, the boot smoke
test and both render tests all run the project **from source**, where the file is
sitting on disk and everything works. That is why CI's screenshots looked
perfect while the shipped game was a void. The export step only ever asserted
that exporting *succeeded*.

Every gate the project had was a statement about the **pipeline**. None was a
statement about the **artifact**.

## Decision

**Every publishable artifact is inspected for the things it must contain.**

- **`tools/verify_pack.sh`** exports, then asserts that every `res://` data and
  asset path referenced in `src/` is genuinely in the pack. The required list is
  **derived from the source**, not hardcoded, so a data file added later is
  covered without anyone remembering.
- **The APK gets its own check**, because Android is a separate preset with its
  own filters. It **extracts** the APK rather than grepping it — the pack may be
  deflated inside the zip, and a raw grep would find nothing and call that a pass.
- **The site is polled for HTTP 200** after publishing ([ADR-0011](0011-pages-from-a-branch.md)).

The gate is tested **in both directions**: it passes now, and reintroducing the
empty `include_filter` makes it fail naming `arena_01.txt` specifically. *A check
that cannot fail is worthless.*

## Consequences

**Good:**
- The failure class is closed, not just the instance. Any future data file is
  covered automatically.
- It generalises: "does the artifact contain what it needs" is now a habit rather
  than a one-off fix.

**Bad:**
- An extra export in CI (~3 s) purely to inspect it.
- The check matches **two path forms**, because the pack stores two: a resource
  keeps its full `res://` path, while a file pulled in by `include_filter` is
  stored without the prefix. Matching only the first form reported the JSON files
  missing when they were present — a false positive found while writing it.
- String-matching a binary pack is crude. It proves the path is recorded, not
  that the bytes are intact.
- **Adding a data file with a new extension still requires editing
  `include_filter` in both presets by hand.** The gate reports the mistake; it
  does not prevent it.

## Consequences beyond this bug

Two related habits came out of the same incident and are worth stating:

- **`continue-on-error` on a publish job is banned.** It is what let a broken
  deploy report green for its entire life.
- **A green *run* is not a green *job*.** Reading a run summary instead of the
  job under it produced a confident wrong diagnosis and a fix that addressed
  nothing. Check the job.

## Alternatives

| | Verdict |
|---|---|
| Rename the arena to `.json` so it is a resource by default | Rejected — the ASCII grid's readability in a diff is the whole point of [ADR-0005](0005-text-first-authoring.md), and it would fix one file rather than the class |
| `export_filter="all_files"` | Rejected — packages tests, tools and screenshots into the shipped game |
| Boot the exported build in CI and assert it loads | **Not rejected — deferred.** Strictly better, but running an exported web build headlessly is real work. The pack check is the affordable 90% |
