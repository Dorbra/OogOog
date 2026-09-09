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
bash tests/test_publish_web.sh                        # CI publish logic
bash tests/test_docs_links.sh                         # no dead doc links
./tests/test_net_loopback.sh "$GODOT"                 # two processes talk
./tools/verify_pack.sh "$GODOT" Web                   # does the EXPORT have the data?
./tools/smoke_test.sh  "$GODOT" 300                   # does it boot?
./tools/render_test.sh "$GODOT" 90  build/shot.png   idle
./tools/render_test.sh "$GODOT" 240 build/combat.png combat
./tools/verify_ui.sh   "$GODOT"                       # can the controls be TOUCHED?
```

**If your change alters how often anyone meets anyone — movement, ranges, bot
behaviour, healing, damage — also run the balance measurement and put the two
distributions in the PR:**

```bash
"$GODOT" --headless --path . --script tools/measure_matches.gd -- 24
```

It plays whole matches and reports the score distribution, how the match was
decided, time to the first kill, and how far an unled shot still hits. Three
balance predictions in this project have been wrong, one by a factor of ten; the
tool exists because arguing about these numbers does not work. It also accepts
`key=value` overrides, so a sweep is a shell loop rather than a series of
commits.

**Then look at the screenshots.** They are the only way to see the game without
a phone, and they have caught bugs no test did: an autoload that failed to
instantiate, a HUD drawn under the camera cutout, targets pushed off-camera by
a zoom change, particles that kept moving during a freeze frame.

### Data files must be added to `include_filter`

Every check above except `verify_pack.sh` runs the project **from source**, where
data files are simply on disk. Exports are different: `export_filter` is
`all_resources`, and Godot only counts things it can import as resources. A
`.json` or `.svg` qualifies. **A `.txt` does not.**

That is not hypothetical. `data/arenas/arena_01.txt` was dropped from every
export for two merged PRs. In the packaged game the arena had zero cells, so the
world had size zero, there were no walls and no spawn points, the ground drew
into an empty rect and the player fell back to the origin — a grey void with a
pond in it. Every test passed the whole time, because every test read the file
straight off the disk.

So: **adding a data file with a new extension means adding it to
`include_filter` in `export_presets.cfg`, in both presets.** `verify_pack.sh`
derives its list from the `res://` literals in `src/`, so it covers new files
automatically — but it can only tell you afterwards.

## What CI does with your PR

| Event | Publishes |
|---|---|
| Open / update a PR | `pr-<n>` prerelease with the APK, a web preview at `/pr/<n>/`, and a sticky comment carrying both |
| Merge to `main` | The rolling `dev` release, and the web build at the site root |
| Close a PR | Removes that PR's preview directory |

Make **`build`** the required status check — that specific check rather than the
whole workflow, so adding a job later cannot silently change what gates a merge.

### Why the web build is published by pushing a branch

Worth knowing, because it cost hours and the failure was invisible.

Pages used to be deployed with `actions/deploy-pages`, which runs the job inside
the **`github-pages` environment**. That environment carries a deployment-branch
policy, and this repository's was pinned to `claude/godot-archer-arena` — the
branch that happened to be default when Pages was first configured. Making
`main` the default branch later did **not** update it.

Every deploy from `main` was then refused *before the job's first step*. The
signature is worth memorising: **a job that fails in about one second, has no
steps, and whose logs 404.** There is nothing to read, because nothing ran. On
top of that the job was `continue-on-error`, so the run reported green while the
site served a build from hours earlier.

Pushing a branch needs `contents: write` and nothing else — no environment, no
branch policy, no gate that can refuse a job before it starts. `tools/publish_web.sh`
does the work; `tests/test_publish_web.sh` proves it against a local bare repo.

Two things about that script are deliberate and easy to break:

- **A root publish must not delete `pr/`.** Those previews belong to pull
  requests that are still open.
- **Every publish rewrites the branch to a single orphan commit.** The debug
  wasm plus the `.pck` are ~37 MB; an ordinary commit per build would put that
  in git history every time — roughly 700 MB after twenty builds, against
  GitHub's 1 GB soft limit. Force-pushing a generated branch nothing checks out
  is the standard practice, not a shortcut.

The publish job also polls the live URL and fails if it never returns 200. The
whole incident was a deploy reporting success while the site stayed stale, so
"it pushed" is not allowed to count as "it published".

## Documentation

Engineering docs live in [`docs/`](docs/) — architecture, game design, CI/CD, and
[ADRs](docs/decisions/) recording why each significant decision was made and what
it cost.

Two rules that matter:

- **An ADR is immutable once merged.** Reversing a decision means a *new* ADR
  that supersedes it; the old file stays. The history of what was believed, and
  why, is the point.
- **A change that invalidates a document updates it in the same PR.** Docs that
  drift are worse than none, because they get believed.

`tests/test_docs_links.sh` checks that every relative link resolves, including in
files not yet committed.

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
