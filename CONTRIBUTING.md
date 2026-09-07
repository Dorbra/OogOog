# Contributing

## The constraint that shapes everything

**This project is developed without a local machine.** Builds happen in GitHub
Actions and get installed on a phone. That single fact explains most of the
decisions here:

- CI is not a safety net beside a dev loop — **it is the dev loop**. A green run
  has to mean "this actually works", not "it compiled".
- Anything that cannot be verified headlessly gets a tool built for it, rather
  than being shipped on hope. That is why there is a screenshot renderer.
- Every value that affects how the game *feels* is a runtime slider, not a
  constant, so it can be settled with thumbs instead of round trips.

## Branching

`main` is protected and always releasable. All work happens on a branch and
lands through a pull request.

| Prefix | For |
|---|---|
| `feat/` | New player-facing capability |
| `fix/` | Something is broken |
| `chore/` | Tooling, CI, refactors, dependencies |
| `docs/` | Documentation only |

One feature per branch, one branch per PR.

## Before you push

Run the same gate CI runs. It takes a couple of minutes and it is much cheaper
than a red build:

```bash
GODOT=/path/to/godot

gdformat $(git ls-files '*.gd')                       # format
gdlint  $(git ls-files '*.gd')                        # lint
"$GODOT" --headless --path . --import                 # import cache
"$GODOT" --headless --path . --script tools/run_tests.gd
./tools/smoke_test.sh  "$GODOT" 300                   # does it boot?
./tools/render_test.sh "$GODOT" 90  build/shot.png   idle
./tools/render_test.sh "$GODOT" 240 build/combat.png combat
```

**Then look at the screenshots.** They are the only way to see the game without
a phone, and they have caught bugs no test did: an autoload that failed to
instantiate, a HUD drawn under the camera cutout, targets pushed off-camera by
a zoom change, particles that kept moving during a freeze frame.

## What CI does with your PR

| Event | Publishes |
|---|---|
| Open / update a PR | `pr-<n>` prerelease with the APK, plus a sticky comment carrying the link |
| Merge to `main` | The rolling `dev` release everyone bookmarks |

Both also deploy the web preview. **GitHub Pages is a single shared environment
for the whole repository**, so with two PRs open it shows whichever built most
recently — the commit hash in the in-game HUD is what tells you which build you
are actually looking at. Per-PR APKs do not have this problem; each gets its own
tag.

## Testing conventions

Tests live in `tests/`, run via `tools/run_tests.gd`, and cover the parts that
are pure logic — the simulation. Rendering is verified by looking at
screenshots, not by asserting on pixels.

Two tests exist specifically to catch silent failures this codebase is prone to:

- **`test_tuning_keys`** — every `Tuning.get_value("…")` key must exist. A
  missing key returns `0.0` with only a pushed error, which on a phone looks
  like "the game is broken" with nothing to point at.
- **`test_assets`** — every referenced `res://assets/…` path must exist *and*
  load as a non-zero texture. Existing is not enough: an SVG that fails to
  rasterise still exists.

### A GDScript trap worth knowing

**Lambdas capture locals by value.** A counter incremented inside a signal
handler never reaches the enclosing scope. This has bitten this project three
times, including in the test suite itself. Accumulate into an `Array` or
`Dictionary` — those are reference types and mutate through the capture.

```gdscript
var hits := 0
world.hit.connect(func(...): hits += 1)   # WRONG — always 0

var hits: Array = []
world.hit.connect(func(...): hits.append(true))   # correct
```
