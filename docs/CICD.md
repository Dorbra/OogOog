# CI/CD

**CI is not a safety net bolted on beside a dev loop here. It *is* the dev loop.**

Nobody working on this project has a machine that can build or run it. Every
artifact anyone has ever played was produced by GitHub Actions. That single fact
sets the bar: a green run has to mean considerably more than "it compiled".

---

## 1. Topology

Two workflows, three triggers, four publish targets.

```
                    ┌──────────────────────────────────────────┐
   pull_request ───▶│  build.yml                                │
   push → main  ───▶│                                           │
   dispatch     ───▶│  ┌────────────┐      ┌─────────────────┐  │
                    │  │   build    │─────▶│   publish-web   │  │
                    │  │            │ web  │                 │  │
                    │  │ 14 gates   │ art. │ push gh-pages   │  │
                    │  │ + exports  │      │ + verify 200    │  │
                    │  └────────────┘      └─────────────────┘  │
                    └──────────────────────────────────────────┘

   PR closed    ───▶  pages-cleanup.yml ──▶ remove pr/<n>/ from gh-pages
```

| Trigger | Validates | Publishes |
|---|---|---|
| `pull_request` → main | everything | `pr-<n>` prerelease + sticky comment + web preview at `/pr/<n>/` |
| `push` → main | everything | rolling `dev` release + web build at the site root |
| `workflow_dispatch` | everything | nothing |
| `pull_request` closed | — | deletes that PR's preview directory |

**Feature branches deliberately have no `push` trigger.** With `pull_request`
active, a branch with an open PR would build twice for the same commit. That is
not just waste — it is how run #10 raced run #8 over a shared publish target and
failed while the identical commit passed.

---

## 2. Delivery channels

| | **Channel A — web** | **Channel B — APK** |
|---|---|---|
| Where | GitHub Pages, from the `gh-pages` branch | GitHub Release asset |
| `main` | site root | `dev` release (bookmark this) |
| A PR | `/pr/<n>/` | `pr-<n>` prerelease |
| Loop | ~3 min, refresh | ~6 min, download + install |
| Good for | Movement, aim, layout, balance | **Performance, thermals, real touch latency** |

**Never judge performance in the browser.** The web export is single-threaded and
its timing does not represent the device. The APK is the source of truth.

> Web is single-threaded because GitHub Pages cannot set the COOP/COEP headers
> that `SharedArrayBuffer` requires, and mobile browsers largely do not support
> the threaded path anyway. A single-threaded build runs anywhere with no special
> headers ([ADR-0006](decisions/0006-two-delivery-channels.md)).

---

## 3. The gates, in order

Each one exists because of a specific failure mode. The ordering is deliberate:
cheapest and most likely to fail first.

| # | Gate | Catches |
|---|---|---|
| 1 | **Version check** — `.godot-version` must equal the workflow's `GODOT_VERSION` | The repo and CI silently drifting to different engines |
| 2 | **`gdformat --check` + `gdlint`** | Style drift; `gdlint` also catches real ordering bugs |
| 3 | **`--import`** — build the `.godot/` cache | The classic green-build-broken-artifact. Skipping this is *the* canonical Godot CI mistake |
| 4 | **Unit tests** — 185 assertions, `tools/run_tests.gd` | Sim logic regressions |
| 5 | **Boot smoke test** — 300 headless frames, fails on any engine or script error | Crash-on-launch, which otherwise costs a full install round trip to discover |
| 6 | **Publish logic tests** — 18 assertions, `tests/test_publish_web.sh` | A root publish deleting open PRs' previews; `gh-pages` history growing unbounded |
| 7 | **Render tests** — idle + combat screenshots under Xvfb | Anything visual. `_draw()` is never called headless, so without this the whole rendering path is unverified |
| 8 | **Pack verification** — `tools/verify_pack.sh` | **Data files missing from the exported artifact** |
| 9 | Web export | A broken web build |
| 10 | Android export | A broken APK |
| 11 | **APK arena check** | The Android preset drifting from the Web preset |

Gates 6, 8 and 11 exist because of bugs that reached a real device. Their stories
are in §7.

### Why the render test is worth its complexity

`godot --headless` never calls `_draw()`. Everything visual — the camera, the
terrain, the cats, every effect — was unverifiable without a phone.

`tools/render_test.sh` runs a real windowed Godot under **Xvfb** with
`LIBGL_ALWAYS_SOFTWARE=1` and `--rendering-driver opengl3`, then writes a PNG.
The combat mode goes further: it **drives scripted input**, fires a real shot,
and captures on the `hit` event plus 7 frames.

This is the highest-leverage tool in the repo. It has caught: an autoload that
failed to instantiate (`get_viewport_rect()` on a `Node`), the HUD drawn under
the Pixel 9's camera cutout, targets pushed off-camera by a zoom change, damage
numbers washed out against grass, and particles that kept flying during a
hitstop freeze. **None of those had a failing test.** Somebody looked at a
picture.

---

## 4. Publishing

### Web: a branch push, not the deployment API

```
gh-pages branch            served at
  /              ──────▶   dorbra.github.io/OogOog/          main
  /pr/3/         ──────▶   dorbra.github.io/OogOog/pr/3/     PR #3
```

`tools/publish_web.sh` clones `gh-pages`, replaces the relevant directory,
writes `.nojekyll`, and force-pushes.

Two properties are load-bearing and easy to break, so `tests/test_publish_web.sh`
pins both:

1. **A root publish must not delete `pr/`.** Those previews belong to pull
   requests that are still open.
2. **Every publish rewrites the branch to a single orphan commit.** The debug
   wasm plus the `.pck` are ~37 MB. An ordinary commit per build would put that
   in git history every time — roughly 700 MB after twenty builds, against
   GitHub's 1 GB soft limit. Force-pushing a generated branch that nothing checks
   out is standard practice, not a shortcut.

**Concurrency:** `build.yml`'s publish job and `pages-cleanup.yml` share the
group `gh-pages-publish` with `cancel-in-progress: false`, because both
force-push the same branch and must queue rather than race.

**The publish job then polls the live URL and fails if it never returns 200.** A
push is not a publish ([ADR-0011](decisions/0011-pages-from-a-branch.md)).

### APK: debug-signed, deliberately

Debug-signed APKs sideload fine, install over each other cleanly, and need
**zero secrets** — no keystore, no base64 blob, no secret management on the
critical path. A release keystore only matters for Play Store distribution, and
it is a 30-minute task on the day that becomes real.

Each PR gets its own `pr-<n>` tag, so two open PRs never fight over one release.
`main` gets the rolling `dev` tag so the bookmarked URL is stable.

---

## 5. Repository settings (not in version control)

These live in GitHub's UI and cannot be set from this repo. They are documented
because **each one has already caused an outage**.

| Setting | Value | If wrong |
|---|---|---|
| Pages → Source | Deploy from a branch → `gh-pages` / `(root)` | Site 404s; the publish job's liveness check fails |
| Environments → `github-pages` → Deployment branches | **No restriction** | GitHub's own `pages-build-deployment` is refused — 1 second, no steps, no logs |
| Branches → `main` | Require a PR; **leave "Require approvals" unchecked** | There is no "0" to select, and any approval requirement deadlocks a solo repo, since GitHub forbids self-approval |
| Required status check | **`build`** | Pick that check specifically, not the whole workflow, so adding a job later cannot silently change what gates a merge |

---

## 6. Local gate

Run before pushing. It is the same set CI runs, minus the Android export.

```bash
GODOT=/path/to/godot

gdformat --check $(git ls-files '*.gd')
gdlint          $(git ls-files '*.gd')
"$GODOT" --headless --path . --import
"$GODOT" --headless --path . --script tools/run_tests.gd
bash tests/test_publish_web.sh
./tools/verify_pack.sh "$GODOT" Web
./tools/smoke_test.sh  "$GODOT" 300
./tools/render_test.sh "$GODOT" 90  build/shot.png   idle
./tools/render_test.sh "$GODOT" 240 build/combat.png combat
```

**Then look at the screenshots.** They are the only way to see the game without a
phone.

---

## 7. Incident log

Post-mortems, kept because each one produced a permanent gate and because the
reasoning is more useful than the fix.

### #1 — Two branches, one commit, two runs, one publish target

Run #10 on `main` **failed** while the *identical commit* passed as run #8 on the
feature branch. Pushing one commit to two branches started two runs that both
drove the single Pages environment and the single rolling `dev` tag.

**Root cause:** shared mutable publish targets with no serialisation.
**Fix:** dropped the push trigger on feature branches; per-event release tags;
publishing moved to its own concurrency group with `cancel-in-progress: false`.

### #2 — A deploy that had never worked, reported green for its whole life

The site served commit `b221e10` for over six hours while `main` moved on.

**Root cause:** the `github-pages` environment's deployment-branch policy was
pinned to `claude/godot-archer-arena` — whichever branch was default when Pages
was first configured. Making `main` the default branch later did **not** update
it. Every deploy from `main` was refused *before the job's first step*.

**The signature is worth memorising: a job that fails in about one second, has no
steps, and whose logs 404.** There is nothing to read because nothing ran.

**Two compounding mistakes, both mine:**

1. `continue-on-error: true` on the deploy job. It kept the *run* green while the
   job failed, so the failure was invisible in the run list. **A check that is
   expected to fail is worse than no check — it trains you to ignore red.**
2. I read a green *run* as a green *job* and reported "run #14 was fully green
   including deploy-pages". It was not. That wrong data point produced a
   confident wrong diagnosis and a fix that addressed nothing.

**Fix:** publish by pushing a branch instead ([ADR-0011](decisions/0011-pages-from-a-branch.md)),
`continue-on-error` removed, and a liveness poll added so a publish cannot report
success unless the site actually answers.

### #3 — The map was never in any build

The live site rendered as a grey void with a pond floating in it.

**Root cause:** `data/arenas/arena_01.txt` had never been inside a single
exported build. `export_filter="all_resources"` with an empty `include_filter`,
and Godot only counts what it can *import* as a resource. `.json` qualifies,
`.svg` qualifies, **`.txt` does not**.

Every symptom followed from that one file: an empty grid → zero-size world →
ground drawn into an empty rect (the grey), no walls, no spawns, the player
falling back to the origin. The pond survived only because it is the one terrain
element that is not view-culled.

**Why nothing caught it:** the unit tests, the smoke test and both render tests
all run the project **from source**, where the file is on disk. That is why CI's
screenshots looked perfect while the shipped game was a void. The export step
only asserted that exporting *succeeded*.

**Fix:** `include_filter="*.txt"` on both presets, plus `tools/verify_pack.sh`,
which exports and asserts every `res://` path referenced in `src/` is genuinely
in the pack. The required list is derived from the source, so a data file added
later is covered without anyone remembering
([ADR-0012](decisions/0012-verify-inside-the-artifact.md)).

**Two bugs hid each other.** The map went missing when the arena merged, but the
site had been frozen on a pre-arena build since incident #2, so fixing the Pages
pipeline is what exposed it.

### The lesson all three share

**Verify the artifact, not the process.** "The job succeeded", "the run is green"
and "the export completed" are all statements about the *pipeline*. None of them
is a statement about the thing a player installs. Every gate added since asserts
something about the artifact itself: the pack contains the map, the APK contains
the map, the site returns 200.

---

## 8. Costs and limits

- **~2 min** for the `build` job (Godot binary and export templates are cached),
  **~1 min** more to publish. About 6 minutes from push to installable APK.
- **`gh-pages` stays at one commit**, so the branch does not grow. Each open PR
  costs ~40 MB of *branch content* until it closes.
- **Fork PRs get no preview.** `GITHUB_TOKEN` is read-only for them, so the
  publish job is skipped by an explicit guard rather than failing confusingly.
- **The web build is a debug export** (36 MB wasm) — a slow first load on mobile
  data. A release-mode export is on the tech-debt list.
- **`dl.google.com` is blocked from the development container**, so there is no
  local Android SDK. Android export is CI-only and cannot be reproduced locally.
