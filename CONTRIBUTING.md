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

Protection is configured as: require a pull request, **Require approvals left
unchecked** (there is no zero to choose, and any approval requirement deadlocks
a solo repo since GitHub forbids self-approval), require the **`build`** status
check, require branches up to date, block force pushes.

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

**Only `main` publishes the web build.** A repository has exactly one Pages
site, and its `github-pages` environment admits only the default branch, so a
deploy from a PR head branch is refused by GitHub before any step of the job
runs — a one-second failure with no logs. Nothing in this repository can
authorise it.

That job used to run on PRs anyway, under `continue-on-error`, which kept the
run green and still painted a red X on every pull request. A check expected to
fail is worse than no check, so it no longer runs there.

So on a PR: **the APK is the preview.** It is also the more honest one — browser
timings never matched the device, and the APK is this exact commit. The web
export still runs and still has to succeed on every PR; only the *deploy* is
skipped.

Making a required status check out of **`build`** (not the whole workflow) is
still the right setting, and now nothing else can go red anyway.

If per-PR web previews ever become worth it, they need Pages served from a
`gh-pages` branch with each PR in its own subdirectory — no environment, no
branch policy, and no last-writer-wins. That is a deliberate change worth its
own PR, not a workaround.

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
